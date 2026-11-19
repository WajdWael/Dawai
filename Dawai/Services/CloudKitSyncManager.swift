//
//  CloudKitSyncManager.swift
//  Dawai
//
//  Cross-device synchronization over CloudKit Public Database (`iCloud.com.wajdwael.dawaiapp`).
//  Uses immutable append-only `DawaiSyncEvent` records so two different Apple IDs (Patient and Caregiver)
//  can both read and write shared patient schedules without hitting CloudKit `_creator` permission errors.
//

import Foundation
import CloudKit
import Combine
import UIKit

// MARK: - Sync Event Model

public enum CloudKitEntityType: String, Codable, Sendable {
    case relationship = "relationship"
    case relationshipEnd = "relationship_end"
    case medication = "medication"
    case medicationDelete = "medication_delete"
    case deletionRequest = "deletion_request"
    case deletionRequestDelete = "deletion_request_delete"
    case doseRecord = "dose_record"
}

public struct CloudKitSyncEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let partitionKey: String
    public let entityType: CloudKitEntityType
    public let entityId: String
    public let updatedAt: Date
    public let payloadJSON: String
    public let imageData: Data?

    public init(
        id: String = UUID().uuidString,
        partitionKey: String,
        entityType: CloudKitEntityType,
        entityId: String,
        updatedAt: Date = Date(),
        payloadJSON: String = "",
        imageData: Data? = nil
    ) {
        self.id = id
        self.partitionKey = partitionKey
        self.entityType = entityType
        self.entityId = entityId
        self.updatedAt = updatedAt
        self.payloadJSON = payloadJSON
        self.imageData = imageData
    }
}

// MARK: - Deterministic Event Reducer (Testable Pure Logic)

public struct ReducedUserPartitionState: Equatable, Sendable {
    public let activeRelationships: [ActiveRelationship]
    public let endedRelationshipIds: Set<UUID>
}

public struct ReducedPatientPartitionState: Equatable, Sendable {
    public let medications: [MedicationItem]
    public let deletedMedicationIds: Set<UUID>
    public let deletionRequests: [MedicationDeletionRequest]
    public let deletedRequestIds: Set<UUID>
    public let doseRecords: [DoseRecord]
}

public enum CloudKitSyncReducer {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    public static func reduceUserEvents(_ events: [CloudKitSyncEvent]) -> ReducedUserPartitionState {
        let sorted = events.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhs.id < rhs.id
        }

        var relationshipsById: [UUID: ActiveRelationship] = [:]
        var endedIds = Set<UUID>()

        for event in sorted {
            guard let uuid = UUID(uuidString: event.entityId) else { continue }
            switch event.entityType {
            case .relationship:
                if let data = event.payloadJSON.data(using: .utf8),
                   let rel = try? decoder.decode(ActiveRelationship.self, from: data) {
                    relationshipsById[uuid] = rel
                    endedIds.remove(uuid)
                }
            case .relationshipEnd:
                relationshipsById.removeValue(forKey: uuid)
                endedIds.insert(uuid)
            default:
                break
            }
        }

        let active = relationshipsById.values
            .filter(\.isActive)
            .sorted { $0.establishedAt < $1.establishedAt }

        return ReducedUserPartitionState(
            activeRelationships: active,
            endedRelationshipIds: endedIds
        )
    }

    public static func reducePatientEvents(
        _ events: [CloudKitSyncEvent],
        calendar: Calendar = .current
    ) -> ReducedPatientPartitionState {
        let sorted = events.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhs.id < rhs.id
        }

        var medicationsById: [UUID: MedicationItem] = [:]
        var deletedMedIds = Set<UUID>()
        var requestsById: [UUID: MedicationDeletionRequest] = [:]
        var deletedReqIds = Set<UUID>()
        var doseRecordsByKey: [String: DoseRecord] = [:]

        for event in sorted {
            switch event.entityType {
            case .medication:
                guard let uuid = UUID(uuidString: event.entityId),
                      let data = event.payloadJSON.data(using: .utf8),
                      var med = try? decoder.decode(MedicationItem.self, from: data) else {
                    continue
                }
                if let imageData = event.imageData {
                    med.imageData = imageData
                } else if let existingImage = medicationsById[uuid]?.imageData {
                    med.imageData = existingImage
                }

                // Preserve same-day slot confirmations across near-concurrent events
                if let previous = medicationsById[uuid] {
                    med = mergeMedicationSlotConfirmations(older: previous, newer: med, calendar: calendar)
                }

                medicationsById[uuid] = med
                deletedMedIds.remove(uuid)

            case .medicationDelete:
                guard let uuid = UUID(uuidString: event.entityId) else { continue }
                medicationsById.removeValue(forKey: uuid)
                deletedMedIds.insert(uuid)

            case .deletionRequest:
                guard let uuid = UUID(uuidString: event.entityId),
                      let data = event.payloadJSON.data(using: .utf8),
                      let req = try? decoder.decode(MedicationDeletionRequest.self, from: data) else {
                    continue
                }
                requestsById[uuid] = req
                deletedReqIds.remove(uuid)

            case .deletionRequestDelete:
                guard let uuid = UUID(uuidString: event.entityId) else { continue }
                requestsById.removeValue(forKey: uuid)
                deletedReqIds.insert(uuid)

            case .doseRecord:
                guard let data = event.payloadJSON.data(using: .utf8),
                      let record = try? decoder.decode(DoseRecord.self, from: data) else {
                    continue
                }
                let dayComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: record.scheduledDate)
                let slotKey = "\(record.medicationId.uuidString)_\(dayComps.year ?? 0)_\(dayComps.month ?? 0)_\(dayComps.day ?? 0)_\(dayComps.hour ?? 0)_\(dayComps.minute ?? 0)"
                if let existing = doseRecordsByKey[slotKey] {
                    // Never downgrade a taken confirmation to missed/upcoming
                    let existingTaken = existing.status == .takenOnTime || existing.status == .takenLate
                    let incomingTaken = record.status == .takenOnTime || record.status == .takenLate
                    if existingTaken && !incomingTaken {
                        continue
                    }
                }
                doseRecordsByKey[slotKey] = record

            case .relationship, .relationshipEnd:
                break
            }
        }

        // Drop orphaned deletion requests whose medications were already deleted
        for (reqId, req) in requestsById where deletedMedIds.contains(req.medicationId) {
            requestsById.removeValue(forKey: reqId)
            deletedReqIds.insert(reqId)
        }

        let meds = medicationsById.values.sorted { $0.createdAt < $1.createdAt }
        let reqs = requestsById.values.sorted { $0.requestedAt < $1.requestedAt }
        let records = doseRecordsByKey.values.sorted { $0.scheduledDate > $1.scheduledDate }

        return ReducedPatientPartitionState(
            medications: meds,
            deletedMedicationIds: deletedMedIds,
            deletionRequests: reqs,
            deletedRequestIds: deletedReqIds,
            doseRecords: records
        )
    }

    private static func mergeMedicationSlotConfirmations(
        older: MedicationItem,
        newer: MedicationItem,
        calendar: Calendar
    ) -> MedicationItem {
        var merged = newer
        let referenceDay = newer.takenAt ?? newer.takenSlotsToday.values.max()
        guard let referenceDay else { return merged }

        for (slot, takenDate) in older.takenSlotsToday where calendar.isDate(takenDate, inSameDayAs: referenceDay) {
            if merged.takenSlotsToday[slot] == nil {
                merged.takenSlotsToday[slot] = takenDate
            }
        }
        if let latest = merged.takenSlotsToday.values.max() {
            merged.takenAt = max(merged.takenAt ?? latest, latest)
        }
        return merged
    }
}

// MARK: - CloudKit Sync Manager

@MainActor
public final class CloudKitSyncManager: ObservableObject {
    public static let shared = CloudKitSyncManager()

    public static let containerIdentifier = "iCloud.com.wajdwael.dawaiapp"
    public static let recordType = "DawaiSyncEvent"

    private static let pendingQueueKey = "dawai_ck_pending_events_v1"
    private static let bootstrappedPatientKeyPrefix = "dawai_ck_bootstrapped_patient_"

    // MARK: - Published UI Status
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var isAccountAvailable: Bool = false
    @Published public private(set) var lastSyncedAt: Date? = nil
    @Published public private(set) var statusMessage: String = "جاري التحقق من اتصال iCloud..."
    @Published public private(set) var lastErrorMessage: String? = nil
    @Published public private(set) var pendingUploadCount: Int = 0

    public var isEnabled: Bool
    private var isApplyingRemoteState: Bool = false
    private var syncTimer: Timer?
    private var subscribedPartitions = Set<String>()
    private var pendingEvents: [CloudKitSyncEvent] = []
    private var flushTask: Task<Void, Never>?

    private lazy var container: CKContainer = CKContainer(identifier: Self.containerIdentifier)
    private var publicDB: CKDatabase { container.publicCloudDatabase }

    private let encoder = JSONEncoder()

    public init(isEnabled: Bool? = nil) {
        let runningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.isEnabled = isEnabled ?? !runningTests
        self.pendingEvents = Self.loadPendingEvents()
        self.pendingUploadCount = self.pendingEvents.count
    }

    // MARK: - Partition Key Helpers

    public static func userPartitionKey(for userId: String) -> String {
        "user:\(userId)"
    }

    public static func patientPartitionKey(for patientId: String) -> String {
        "patient:\(patientId)"
    }

    // MARK: - Lifecycle & Periodic Sync

    public func startPeriodicSync() {
        guard isEnabled else { return }
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.syncNow(silent: true)
            }
        }
        Task {
            await syncNow(silent: true)
        }
    }

    public func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    public func clearPendingQueue() {
        pendingEvents = []
        pendingUploadCount = 0
        UserDefaults.standard.removeObject(forKey: Self.pendingQueueKey)
    }

    // MARK: - Outbound Publish Hooks (Called by Services)

    public func publishRelationship(_ relationship: ActiveRelationship) {
        guard isEnabled, !isApplyingRemoteState else { return }
        guard let json = encodeJSON(relationship) else { return }
        let now = Date()

        enqueueEvent(CloudKitSyncEvent(
            partitionKey: Self.userPartitionKey(for: relationship.patientId),
            entityType: .relationship,
            entityId: relationship.id.uuidString,
            updatedAt: now,
            payloadJSON: json
        ))
        enqueueEvent(CloudKitSyncEvent(
            partitionKey: Self.userPartitionKey(for: relationship.caregiverId),
            entityType: .relationship,
            entityId: relationship.id.uuidString,
            updatedAt: now,
            payloadJSON: json
        ))

        // Immediately publish existing local patient data if this device holds records for this patient
        publishAllLocalPatientData(patientId: relationship.patientId)
        triggerBackgroundFlushAndSync()
    }

    public func publishRelationshipEnded(_ relationship: ActiveRelationship) {
        guard isEnabled, !isApplyingRemoteState else { return }
        let now = Date()

        enqueueEvent(CloudKitSyncEvent(
            partitionKey: Self.userPartitionKey(for: relationship.patientId),
            entityType: .relationshipEnd,
            entityId: relationship.id.uuidString,
            updatedAt: now
        ))
        enqueueEvent(CloudKitSyncEvent(
            partitionKey: Self.userPartitionKey(for: relationship.caregiverId),
            entityType: .relationshipEnd,
            entityId: relationship.id.uuidString,
            updatedAt: now
        ))
        triggerBackgroundFlush()
    }

    public func publishMedication(_ medication: MedicationItem) {
        guard isEnabled, !isApplyingRemoteState else { return }
        guard !medication.patientId.isEmpty, medication.patientId != MedicationItem.fallbackPatientId else { return }

        var stripped = medication
        let compressedImage = compressImageIfNeeded(medication.imageData)
        stripped.imageData = nil

        guard let json = encodeJSON(stripped) else { return }
        enqueueEvent(CloudKitSyncEvent(
            partitionKey: Self.patientPartitionKey(for: medication.patientId),
            entityType: .medication,
            entityId: medication.id.uuidString,
            updatedAt: Date(),
            payloadJSON: json,
            imageData: compressedImage
        ))
        triggerBackgroundFlush()
    }

    public func publishMedicationDeletion(medicationId: UUID, patientId: String) {
        guard isEnabled, !isApplyingRemoteState else { return }
        guard !patientId.isEmpty, patientId != MedicationItem.fallbackPatientId else { return }

        enqueueEvent(CloudKitSyncEvent(
            partitionKey: Self.patientPartitionKey(for: patientId),
            entityType: .medicationDelete,
            entityId: medicationId.uuidString,
            updatedAt: Date()
        ))
        triggerBackgroundFlush()
    }

    public func publishDeletionRequest(_ request: MedicationDeletionRequest) {
        guard isEnabled, !isApplyingRemoteState else { return }
        guard !request.patientId.isEmpty, request.patientId != MedicationItem.fallbackPatientId else { return }
        guard let json = encodeJSON(request) else { return }

        enqueueEvent(CloudKitSyncEvent(
            partitionKey: Self.patientPartitionKey(for: request.patientId),
            entityType: .deletionRequest,
            entityId: request.id.uuidString,
            updatedAt: Date(),
            payloadJSON: json
        ))
        triggerBackgroundFlush()
    }

    public func publishDeletionRequestRemoval(requestId: UUID, patientId: String) {
        guard isEnabled, !isApplyingRemoteState else { return }
        guard !patientId.isEmpty, patientId != MedicationItem.fallbackPatientId else { return }

        enqueueEvent(CloudKitSyncEvent(
            partitionKey: Self.patientPartitionKey(for: patientId),
            entityType: .deletionRequestDelete,
            entityId: requestId.uuidString,
            updatedAt: Date()
        ))
        triggerBackgroundFlush()
    }

    public func publishDoseRecord(_ record: DoseRecord) {
        guard isEnabled, !isApplyingRemoteState else { return }
        guard !record.patientId.isEmpty, record.patientId != MedicationItem.fallbackPatientId else { return }
        guard let json = encodeJSON(record) else { return }

        enqueueEvent(CloudKitSyncEvent(
            partitionKey: Self.patientPartitionKey(for: record.patientId),
            entityType: .doseRecord,
            entityId: record.id.uuidString,
            updatedAt: Date(),
            payloadJSON: json
        ))
        triggerBackgroundFlush()
    }

    private func publishAllLocalPatientData(patientId: String) {
        guard !patientId.isEmpty, patientId != MedicationItem.fallbackPatientId else { return }
        let meds = MedicationService.shared.medicationList(forPatient: patientId)
        for med in meds {
            publishMedication(med)
        }
        let reqs = MedicationService.shared.pendingDeletionRequests.filter { $0.patientId == patientId }
        for req in reqs {
            publishDeletionRequest(req)
        }
        let records = AdherenceService.shared.records(forPatient: patientId)
        for rec in records {
            publishDoseRecord(rec)
        }
    }

    // MARK: - Full Bidirectional Sync

    public func syncNow(silent: Bool = false) async {
        guard isEnabled else { return }
        guard !isSyncing else { return }
        guard let identity = KeychainService.shared.loadUserIdentity() else {
            statusMessage = "بانتظار إعداد الحساب"
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                isAccountAvailable = false
                statusMessage = Self.arabicMessage(for: accountStatus)
                lastErrorMessage = statusMessage
                return
            }
            isAccountAvailable = true

            // 1. One-time bootstrap push for existing local data of this user
            bootstrapLocalDataIfNeeded(for: identity)

            // 2. Push any queued local changes first
            try await flushPendingEvents()

            // 3. Pull user partition (relationships established or ended by the other party)
            let userKey = Self.userPartitionKey(for: identity.id)
            let userEvents = try await fetchEvents(forPartitionKey: userKey)
            let userState = CloudKitSyncReducer.reduceUserEvents(userEvents)

            isApplyingRemoteState = true
            RelationshipService.shared.applyRemoteRelationships(
                active: userState.activeRelationships,
                endedIds: userState.endedRelationshipIds
            )
            isApplyingRemoteState = false

            // 4. Determine all patient partitions relevant to this user
            var patientIds = Set<String>()
            if identity.role == .patient {
                patientIds.insert(identity.id)
            } else {
                for rel in RelationshipService.shared.activeRelationships
                where rel.caregiverId == identity.id && rel.isActive {
                    patientIds.insert(rel.patientId)
                }
            }

            // 5. Pull and apply each patient partition
            for patientId in patientIds {
                let patientKey = Self.patientPartitionKey(for: patientId)
                let patientEvents = try await fetchEvents(forPartitionKey: patientKey)
                let patientState = CloudKitSyncReducer.reducePatientEvents(patientEvents)

                isApplyingRemoteState = true
                MedicationService.shared.applyRemotePatientState(
                    patientId: patientId,
                    medications: patientState.medications,
                    deletedMedicationIds: patientState.deletedMedicationIds,
                    deletionRequests: patientState.deletionRequests,
                    deletedRequestIds: patientState.deletedRequestIds
                )
                AdherenceService.shared.applyRemoteDoseRecords(
                    patientState.doseRecords,
                    forPatient: patientId
                )
                isApplyingRemoteState = false

                await ensureSubscriptionIfNeeded(forPartitionKey: patientKey)
            }

            // 6. Ensure silent push subscription on user partition
            await ensureSubscriptionIfNeeded(forPartitionKey: userKey)

            lastSyncedAt = Date()
            lastErrorMessage = nil
            statusMessage = "متصل بـ iCloud ومتزامن"
        } catch {
            isApplyingRemoteState = false
            let friendly = Self.arabicMessage(for: error)
            lastErrorMessage = friendly
            statusMessage = friendly
            if !silent {
                RelationshipService.shared.showToast(friendly)
            }
        }
    }

    /// Handles silent CloudKit remote notifications delivered via AppDelegate.
    public func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard isEnabled else { return .noData }
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            return .noData
        }
        await syncNow(silent: true)
        return .newData
    }

    // MARK: - CloudKit Low-Level Operations

    private func bootstrapLocalDataIfNeeded(for identity: UserIdentity) {
        let key = Self.bootstrappedPatientKeyPrefix + identity.id
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        if identity.role == .patient {
            publishAllLocalPatientData(patientId: identity.id)
        }
        for rel in RelationshipService.shared.activeRelationships where rel.isActive {
            if rel.patientId == identity.id || rel.caregiverId == identity.id {
                publishRelationship(rel)
            }
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    private func enqueueEvent(_ event: CloudKitSyncEvent) {
        pendingEvents.append(event)
        pendingUploadCount = pendingEvents.count
        Self.savePendingEvents(pendingEvents)
    }

    private func triggerBackgroundFlush() {
        flushTask?.cancel()
        flushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let status = try await self.container.accountStatus()
                guard status == .available else {
                    self.isAccountAvailable = false
                    self.statusMessage = Self.arabicMessage(for: status)
                    return
                }
                self.isAccountAvailable = true
                try await self.flushPendingEvents()
                self.lastSyncedAt = Date()
                self.lastErrorMessage = nil
                self.statusMessage = "متصل بـ iCloud ومتزامن"
            } catch {
                self.lastErrorMessage = Self.arabicMessage(for: error)
                self.statusMessage = self.lastErrorMessage ?? "تعذر المزامنة مع iCloud"
            }
        }
    }

    public func triggerBackgroundFlushAndSync() {
        Task { @MainActor [weak self] in
            await self?.syncNow(silent: true)
        }
    }

    private func flushPendingEvents() async throws {
        guard !pendingEvents.isEmpty else { return }

        var remaining: [CloudKitSyncEvent] = []
        var firstError: Error?

        for event in pendingEvents {
            do {
                try await uploadEvent(event)
            } catch {
                remaining.append(event)
                if firstError == nil {
                    firstError = error
                }
            }
        }

        pendingEvents = remaining
        pendingUploadCount = pendingEvents.count
        Self.savePendingEvents(pendingEvents)

        if let firstError {
            throw firstError
        }
    }

    private func uploadEvent(_ event: CloudKitSyncEvent) async throws {
        let recordID = CKRecord.ID(recordName: event.id)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["partitionKey"] = event.partitionKey as CKRecordValue
        record["entityType"] = event.entityType.rawValue as CKRecordValue
        record["entityId"] = event.entityId as CKRecordValue
        record["updatedAt"] = event.updatedAt as CKRecordValue
        record["payload"] = event.payloadJSON as CKRecordValue

        var tempFileURL: URL?
        if let imageData = event.imageData {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("dawai_ck_\(event.id).jpg")
            try imageData.write(to: tempURL, options: .atomic)
            record["imageAsset"] = CKAsset(fileURL: tempURL)
            tempFileURL = tempURL
        }

        defer {
            if let tempFileURL {
                try? FileManager.default.removeItem(at: tempFileURL)
            }
        }

        do {
            _ = try await publicDB.save(record)
        } catch let ckError as CKError where ckError.code == .serverRecordChanged {
            // Already uploaded with the same unique recordName -> idempotent success
            return
        }
    }

    private func fetchEvents(forPartitionKey partitionKey: String) async throws -> [CloudKitSyncEvent] {
        // Query only on `partitionKey` (no sortDescriptors) so only a single Queryable index on `partitionKey` is required.
        let predicate = NSPredicate(format: "partitionKey == %@", partitionKey)
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)

        var fetchedRecords: [CKRecord] = []

        do {
            let (firstBatch, initialCursor) = try await publicDB.records(
                matching: query,
                inZoneWith: nil,
                desiredKeys: ["partitionKey", "entityType", "entityId", "updatedAt", "payload", "imageAsset"],
                resultsLimit: CKQueryOperation.maximumResults
            )
            for (_, result) in firstBatch {
                if case .success(let record) = result {
                    fetchedRecords.append(record)
                }
            }

            var cursor = initialCursor
            while let activeCursor = cursor {
                let (nextBatch, nextCursor) = try await publicDB.records(
                    continuingMatchFrom: activeCursor,
                    desiredKeys: ["partitionKey", "entityType", "entityId", "updatedAt", "payload", "imageAsset"],
                    resultsLimit: CKQueryOperation.maximumResults
                )
                for (_, result) in nextBatch {
                    if case .success(let record) = result {
                        fetchedRecords.append(record)
                    }
                }
                cursor = nextCursor
            }
        } catch let ckError as CKError where ckError.code == .unknownItem {
            // Record type does not exist yet in this environment (e.g. brand-new empty DB in Debug).
            return []
        }

        return fetchedRecords.compactMap { Self.event(from: $0) }
    }

    private static func event(from record: CKRecord) -> CloudKitSyncEvent? {
        guard let partitionKey = record["partitionKey"] as? String,
              let typeRaw = record["entityType"] as? String,
              let entityType = CloudKitEntityType(rawValue: typeRaw),
              let entityId = record["entityId"] as? String else {
            return nil
        }

        let updatedAt = (record["updatedAt"] as? Date) ?? record.creationDate ?? Date()
        let payloadJSON = (record["payload"] as? String) ?? ""

        var imageData: Data?
        if let asset = record["imageAsset"] as? CKAsset,
           let url = asset.fileURL {
            imageData = try? Data(contentsOf: url)
        }

        return CloudKitSyncEvent(
            id: record.recordID.recordName,
            partitionKey: partitionKey,
            entityType: entityType,
            entityId: entityId,
            updatedAt: updatedAt,
            payloadJSON: payloadJSON,
            imageData: imageData
        )
    }

    private func ensureSubscriptionIfNeeded(forPartitionKey partitionKey: String) async {
        guard !subscribedPartitions.contains(partitionKey) else { return }
        let safeId = "sub_" + partitionKey.replacingOccurrences(of: ":", with: "_")
        let predicate = NSPredicate(format: "partitionKey == %@", partitionKey)
        let subscription = CKQuerySubscription(
            recordType: Self.recordType,
            predicate: predicate,
            subscriptionID: safeId,
            options: [.firesOnRecordCreation]
        )

        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info

        do {
            _ = try await publicDB.save(subscription)
            subscribedPartitions.insert(partitionKey)
        } catch let ckError as CKError where ckError.code == .serverRejectedRequest || ckError.code == .serverRecordChanged {
            // Duplicate or already registered
            subscribedPartitions.insert(partitionKey)
        } catch {
            // Non-fatal: periodic polling & foreground sync still keep data up to date
        }
    }

    // MARK: - Helpers

    private func encodeJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func compressImageIfNeeded(_ data: Data?) -> Data? {
        guard let data else { return nil }
        if data.count <= 200_000 { return data }
        guard let image = UIImage(data: data) else { return nil }
        return image.jpegData(compressionQuality: 0.55)
    }

    private static func loadPendingEvents() -> [CloudKitSyncEvent] {
        guard let data = UserDefaults.standard.data(forKey: pendingQueueKey),
              let decoded = try? JSONDecoder().decode([CloudKitSyncEvent].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func savePendingEvents(_ events: [CloudKitSyncEvent]) {
        if events.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingQueueKey)
            return
        }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: pendingQueueKey)
        }
    }

    private static func arabicMessage(for status: CKAccountStatus) -> String {
        switch status {
        case .available:
            return "متصل بـ iCloud ومتزامن"
        case .noAccount:
            return "يرجى تسجيل الدخول إلى iCloud من إعدادات الجهاز لتفعيل المزامنة"
        case .restricted:
            return "حساب iCloud مقيد على هذا الجهاز"
        case .couldNotDetermine, .temporarilyUnavailable:
            return "تعذر التحقق من حساب iCloud حالياً"
        @unknown default:
            return "حالة iCloud غير معروفة"
        }
    }

    private static func arabicMessage(for error: Error) -> String {
        guard let ckError = error as? CKError else {
            return "تعذر الاتصال بـ iCloud: \(error.localizedDescription)"
        }
        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            return "لا يوجد اتصال بالإنترنت — ستتم المزامنة تلقائياً عند عودة الاتصال"
        case .notAuthenticated:
            return "يرجى تسجيل الدخول إلى iCloud من إعدادات الجهاز"
        case .badContainer, .missingEntitlement:
            return "لم يتم تفعيل حاوية iCloud CloudKit في المشروع بعد"
        case .invalidArguments, .unknownItem:
            return "تأكد من تفعيل فهرس partitionKey ونشر CloudKit Schema إلى Production"
        case .permissionFailure:
            return "خطأ صلاحيات في CloudKit"
        default:
            return "تعذر المزامنة مع iCloud (\(ckError.code.rawValue))"
        }
    }
}

