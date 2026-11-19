//
//  MedicationService.swift
//  Dawai
//
//  Use-Case 3 (UC-3): Add Medication
//  Service managing medication lifecycle, input validation, persistence,
//  authorization checks, and local reminder notification scheduling.
//

import Foundation
import Combine
import SwiftUI
import UIKit
import UserNotifications

@MainActor
public final class MedicationService: ObservableObject {
    public static let shared = MedicationService()

    // MARK: - Published State
    /// Every medication stored on this device, for all patients. Screens should not list this directly:
    /// use `medications` (the patient using this device) or `medicationList(forPatient:)` / `daySchedule(forPatient:)`.
    @Published public private(set) var allMedications: [MedicationItem] = []
    /// Medications owned by the patient using this device (`currentPatientId`).
    @Published public private(set) var medications: [MedicationItem] = []
    /// Patient whose schedule drives `medications`, `todayMedications`, `activeMedications`, `activeMedication`, `upcomingDoses` and `remainingDoses`.
    @Published public private(set) var currentPatientId: String = MedicationItem.fallbackPatientId
    @Published public var activeDoses: [ScheduledDose] = []
    @Published public var activeMedications: [MedicationItem] = []
    @Published public var activeMedication: MedicationItem?
    @Published public var upcomingDoses: [UpcomingDose] = []
    /// Untaken doses scheduled for today. Always derived from the real schedule in `refreshDerivedState()`.
    @Published public var remainingDoses: Int = 0

    // MARK: - Use-Case 12 (UC-12): Today's Medications & Auto-Sorting State
    @Published public private(set) var todayDoses: [ScheduledDose] = []
    @Published public private(set) var todayMedications: [MedicationItem] = []
    @Published public private(set) var lastEvaluatedAt: Date = AppClock.shared.now
    private var timeProgressionTimer: AnyCancellable?
    private var dayChangeCancellables = Set<AnyCancellable>()

    // MARK: - Use-Case 11 (UC-11): Collaborative Medication Deletion State
    @Published public private(set) var pendingDeletionRequests: [MedicationDeletionRequest] = []

    // Feedback & Toast notifications
    @Published public var toastMessage: String? = nil
    @Published public var notificationWarning: String? = nil

    /// Persistence for medications and deletion requests (UserDefaults today, replaceable later).
    private let store: any MedicationStore
    private let adherenceService: AdherenceService
    private let relationshipService: RelationshipService
    private let schedulesSystemNotifications: Bool
    private let maxImageSizeBytes = 5 * 1024 * 1024 // 5 MB (UC-3 S#4)

    // MARK: - Image Compression Helper
    public static func compressAndNormalizeImage(_ image: UIImage, maxDimension: CGFloat = 900) -> (image: UIImage, data: Data)? {
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }

        let maxSide = max(originalSize.width, originalSize.height)
        let scaleFactor = maxSide > maxDimension ? (maxDimension / maxSide) : 1.0
        let targetSize = CGSize(
            width: round(originalSize.width * scaleFactor),
            height: round(originalSize.height * scaleFactor)
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        var quality: CGFloat = 0.78
        var jpegData = resizedImage.jpegData(compressionQuality: quality)
        while let current = jpegData, current.count > 900_000, quality > 0.3 {
            quality -= 0.15
            jpegData = resizedImage.jpegData(compressionQuality: quality)
        }

        guard let finalData = jpegData else { return nil }
        return (resizedImage, finalData)
    }

    public static let doseReminderCategoryIdentifier = "DAWAI_DOSE_REMINDER_CATEGORY"
    public static let confirmDoseActionIdentifier = "DAWAI_CONFIRM_DOSE_ACTION"

    public init(
        store: any MedicationStore = UserDefaultsMedicationStore(),
        adherenceService: AdherenceService? = nil,
        relationshipService: RelationshipService? = nil,
        enableTimersAndObservers: Bool = true,
        schedulesSystemNotifications: Bool = true
    ) {
        self.store = store
        self.adherenceService = adherenceService ?? .shared
        self.relationshipService = relationshipService ?? .shared
        self.schedulesSystemNotifications = schedulesSystemNotifications
        if enableTimersAndObservers {
            registerNotificationCategories()
        }
        loadPersistedMedications()
        loadPersistedDeletionRequests()
        if enableTimersAndObservers {
            setupTimeProgressionTimer()
            setupDayChangeObservers()
        }
    }

    private func registerNotificationCategories() {
        let confirmAction = UNNotificationAction(
            identifier: Self.confirmDoseActionIdentifier,
            title: "أخذت الدواء",
            options: [.authenticationRequired]
        )
        let category = UNNotificationCategory(
            identifier: Self.doseReminderCategoryIdentifier,
            actions: [confirmAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - UC-12 S#3: Time Progresses (Auto-updates schedule as time passes)
    private func setupTimeProgressionTimer() {
        timeProgressionTimer = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshDerivedState()
            }
    }

    private func setupDayChangeObservers() {
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .merge(with: NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshDerivedState()
            }
            .store(in: &dayChangeCancellables)
    }

    // MARK: - Persistence & Initial State
    public func loadPersistedMedications() {
        let identity = KeychainService.shared.loadUserIdentity()
        // Items saved before `patientId` existed are assigned to the identity using this device.
        // A new user starts with no medications.
        let stored = store.loadMedications(legacyPatientId: identity?.id ?? MedicationItem.fallbackPatientId)
        self.allMedications = stored.map { item in
            var m = item
            m.timeString = m.timeString.westernNumerals
            m.dosage = m.dosage.westernNumerals
            return m
        }
        reassignLegacyCaregiverMedications(identity: identity)
        refreshDerivedState()
    }

    /// A caregiver never owns medications. Legacy items on a caregiver's device were assigned to the caregiver's
    /// own id when decoded; when exactly one patient is linked, they can only belong to that patient.
    private func reassignLegacyCaregiverMedications(identity: UserIdentity?) {
        guard let identity, identity.role == .caregiver else { return }
        let linkedPatientIds = Set(
            relationshipService.activeRelationships
                .filter { $0.caregiverId == identity.id && $0.isActive }
                .map(\.patientId)
        )
        guard linkedPatientIds.count == 1, let patientId = linkedPatientIds.first else { return }

        var changed = false
        for idx in allMedications.indices where allMedications[idx].patientId == identity.id {
            allMedications[idx].patientId = patientId
            changed = true
        }
        if changed {
            persistMedications()
        }
    }

    /// Medications owned by `patientId`.
    public func medicationList(forPatient patientId: String) -> [MedicationItem] {
        allMedications.filter { $0.patientId == patientId }
    }

    /// Imports/synchronizes a patient's medications and deletion requests from a cross-device sync payload.
    public func importSyncedPatientData(
        patientId: String,
        medications importedMeds: [MedicationItem],
        deletionRequests importedRequests: [MedicationDeletionRequest]
    ) {
        allMedications.removeAll { $0.patientId == patientId }
        let normalizedMeds = importedMeds.map { item -> MedicationItem in
            var m = item
            m.patientId = patientId
            m.timeString = m.timeString.westernNumerals
            m.dosage = m.dosage.westernNumerals
            return m
        }
        allMedications.append(contentsOf: normalizedMeds)

        pendingDeletionRequests.removeAll { $0.patientId == patientId }
        pendingDeletionRequests.append(contentsOf: importedRequests.filter { $0.patientId == patientId })

        persistMedications()
        persistDeletionRequests()
        refreshDerivedState()
    }

    /// Tracks which patients have completed at least one CloudKit pull in this session so initial backfill doesn't spam notifications.
    private var syncedPatientsInSession = Set<String>()

    /// Merges remote CloudKit state for `patientId` without re-publishing, syncs local iOS reminders on the patient's device,
    /// and delivers real local notifications + toasts for cross-device updates (adds, edits, deletions, deletion requests, dose confirmations).
    public func applyRemotePatientState(
        patientId: String,
        medications remoteMedications: [MedicationItem],
        deletedMedicationIds: Set<UUID>,
        deletionRequests remoteRequests: [MedicationDeletionRequest],
        deletedRequestIds: Set<UUID>
    ) {
        let now = AppClock.shared.now
        let calendar = Calendar.current
        let currentIdentity = KeychainService.shared.loadUserIdentity()
        let isLocalPatientDevice = currentIdentity?.id == patientId
        let isLinkedCaregiverDevice = currentIdentity?.role == .caregiver
            && relationshipService.activeRelationships.contains {
                $0.caregiverId == currentIdentity?.id && $0.patientId == patientId && $0.isActive
            }
        let patientName = relationshipService.activeRelationships
            .first(where: { $0.patientId == patientId })?.patientDisplayName ?? "المستفيد"
        let hasCompletedInitialSync = syncedPatientsInSession.contains(patientId)

        var medsChanged = false
        var requestsChanged = false
        var medsToSchedule: [MedicationItem] = []
        var alertsToDeliver: [(title: String, body: String)] = []

        // 1. Apply remote deletions
        if !deletedMedicationIds.isEmpty {
            let toRemove = allMedications.filter { $0.patientId == patientId && deletedMedicationIds.contains($0.id) }
            if !toRemove.isEmpty {
                for removed in toRemove {
                    cancelReminder(id: removed.id)
                    if hasCompletedInitialSync {
                        if isLocalPatientDevice {
                            alertsToDeliver.append((
                                title: "تم حذف دواء من جدولك",
                                body: "تم حذف دواء «\(removed.name)» وإلغاء تذكيراته."
                            ))
                        } else if isLinkedCaregiverDevice {
                            alertsToDeliver.append((
                                title: "حذف دواء • \(patientName)",
                                body: "تم حذف دواء «\(removed.name)» من جدول \(patientName)."
                            ))
                        }
                    }
                }
                allMedications.removeAll { $0.patientId == patientId && deletedMedicationIds.contains($0.id) }
                medsChanged = true
            }
        }

        // 2. Upsert remote medications (preserving same-day local confirmations)
        for remote in remoteMedications where !deletedMedicationIds.contains(remote.id) {
            var incoming = remote
            incoming.patientId = patientId
            incoming.timeString = incoming.timeString.westernNumerals
            incoming.dosage = incoming.dosage.westernNumerals

            if let idx = allMedications.firstIndex(where: { $0.id == incoming.id }) {
                let existing = allMedications[idx]
                let previousTodaySlotCount = existing.takenSlotsToday.values.filter {
                    calendar.isDate($0, inSameDayAs: now)
                }.count

                // Merge same-day slot confirmations so neither side loses a freshly confirmed slot
                for (slot, localTakenAt) in existing.takenSlotsToday where calendar.isDate(localTakenAt, inSameDayAs: now) {
                    if incoming.takenSlotsToday[slot] == nil {
                        incoming.takenSlotsToday[slot] = localTakenAt
                    }
                }
                let slots = dailyDoseTimesMinutes(for: incoming)
                if !incoming.takenSlotsToday.isEmpty {
                    let todaySlots = incoming.takenSlotsToday.filter { calendar.isDate($0.value, inSameDayAs: now) }
                    if !todaySlots.isEmpty {
                        incoming.takenAt = todaySlots.values.max()
                        incoming.isTaken = !slots.isEmpty && slots.allSatisfy { todaySlots[$0] != nil }
                    }
                }

                if existing != incoming {
                    let scheduleChanged =
                        existing.timeString != incoming.timeString ||
                        existing.frequency != incoming.frequency ||
                        existing.days != incoming.days ||
                        existing.selectedWeekdays != incoming.selectedWeekdays ||
                        existing.name != incoming.name ||
                        existing.dosage != incoming.dosage ||
                        existing.instructions != incoming.instructions
                    let newTodaySlotCount = incoming.takenSlotsToday.values.filter {
                        calendar.isDate($0, inSameDayAs: now)
                    }.count
                    let doseNewlyConfirmed = newTodaySlotCount > previousTodaySlotCount || (!existing.isTaken && incoming.isTaken)

                    allMedications[idx] = incoming
                    medsChanged = true
                    if isLocalPatientDevice && scheduleChanged {
                        medsToSchedule.append(incoming)
                    }

                    if hasCompletedInitialSync {
                        if isLinkedCaregiverDevice && scheduleChanged {
                            alertsToDeliver.append((
                                title: "تحديث دواء • \(patientName)",
                                body: "قام \(patientName) بتعديل دواء «\(incoming.name)» (\(incoming.dosage) • \(incoming.timeString))."
                            ))
                        } else if isLinkedCaregiverDevice && doseNewlyConfirmed {
                            alertsToDeliver.append((
                                title: "تأكيد جرعة • \(patientName)",
                                body: "أكد \(patientName) أخذ جرعة «\(incoming.name)» ✅"
                            ))
                        } else if isLocalPatientDevice && scheduleChanged {
                            alertsToDeliver.append((
                                title: "تم تحديث دواء في جدولك",
                                body: "تم تعديل دواء «\(incoming.name)» (\(incoming.dosage) • \(incoming.timeString))."
                            ))
                        }
                    }
                }
            } else {
                allMedications.insert(incoming, at: 0)
                medsChanged = true
                if isLocalPatientDevice {
                    medsToSchedule.append(incoming)
                }
                if hasCompletedInitialSync {
                    if isLocalPatientDevice {
                        alertsToDeliver.append((
                            title: "دواء جديد في جدولك",
                            body: "تمت إضافة دواء «\(incoming.name)» (\(incoming.dosage) • \(incoming.timeString)) وجدولة تنبيهاته."
                        ))
                    } else if isLinkedCaregiverDevice {
                        alertsToDeliver.append((
                            title: "إضافة دواء جديد • \(patientName)",
                            body: "أضاف \(patientName) دواء «\(incoming.name)» (\(incoming.dosage) • \(incoming.timeString))."
                        ))
                    }
                }
            }
        }

        // 3. Apply remote deletion request removals & upserts
        let beforeReqCount = pendingDeletionRequests.count
        pendingDeletionRequests.removeAll { req in
            req.patientId == patientId &&
            (deletedRequestIds.contains(req.id) || deletedMedicationIds.contains(req.medicationId))
        }
        if pendingDeletionRequests.count != beforeReqCount {
            requestsChanged = true
        }

        for remoteReq in remoteRequests
        where remoteReq.patientId == patientId &&
              !deletedRequestIds.contains(remoteReq.id) &&
              !deletedMedicationIds.contains(remoteReq.medicationId) {
            if let idx = pendingDeletionRequests.firstIndex(where: { $0.id == remoteReq.id }) {
                if pendingDeletionRequests[idx] != remoteReq {
                    pendingDeletionRequests[idx] = remoteReq
                    requestsChanged = true
                }
            } else {
                pendingDeletionRequests.append(remoteReq)
                requestsChanged = true
                if isLinkedCaregiverDevice {
                    alertsToDeliver.append((
                        title: "طلب حذف دواء من \(remoteReq.patientDisplayName)",
                        body: "يطلب حذف دواء «\(remoteReq.medicationName)» (\(remoteReq.timeString)). افتح التطبيق للموافقة أو الرفض."
                    ))
                }
            }
        }

        syncedPatientsInSession.insert(patientId)

        if medsChanged {
            persistMedications()
        }
        if requestsChanged {
            persistDeletionRequests()
        }
        if medsChanged || requestsChanged {
            refreshDerivedState(at: now)
        }

        if schedulesSystemNotifications && !medsToSchedule.isEmpty {
            for med in medsToSchedule {
                Task { _ = await self.scheduleReminder(for: med) }
            }
        }

        if !alertsToDeliver.isEmpty {
            if let latest = alertsToDeliver.last {
                showToast("🔔 \(latest.title): \(latest.body)")
            }
            if schedulesSystemNotifications {
                for alert in alertsToDeliver {
                    deliverImmediateSyncNotification(title: alert.title, body: alert.body)
                }
            }
        }
    }

    private func deliverImmediateSyncNotification(title: String, body: String) {
        let enabled = UserDefaults.standard.object(forKey: "dawai_notifications_enabled") as? Bool ?? true
        guard enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "dawai_sync_alert_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Reset (wipes all medication data on this device)
    public func resetAllData() {
        if schedulesSystemNotifications {
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
            MedicationAlarmService.shared.cancelAllAlarms()
            DoseLiveActivityManager.shared.endAllActivities()
        }

        allMedications = []
        pendingDeletionRequests = []
        toastMessage = nil
        notificationWarning = nil

        store.removeAll()
        refreshDerivedState()
    }

    // MARK: - Demo data (Loaded on request from Settings for testing)
    public func loadDemoData() {
        // A patient owns the demo medications; on a caregiver's device they belong to the demo beneficiaries.
        let identity = KeychainService.shared.loadUserIdentity()
        let owner = identity?.role == .patient ? (identity?.id ?? MedicationItem.fallbackPatientId) : MedicationItem.fallbackPatientId
        var demoAspirin = HomeMockData.activeMedication
        demoAspirin.patientId = owner
        allMedications = [
            demoAspirin,
            MedicationItem(patientId: owner, name: "ميترفين", dosage: "حبة واحدة بعد الأكل", timeString: "12:00 ص", scheduledDate: nil, days: ["كل يوم"], frequency: "مرة يوميًا"),
            MedicationItem(patientId: owner, name: "فيتامين د", dosage: "قطرة واحدة يوميًا", timeString: "10:00 ص", scheduledDate: nil, days: ["كل يوم"], frequency: "مرة يوميًا")
        ]
        persistMedications()
        refreshDerivedState()
    }

    private func persistMedications() {
        store.saveMedications(allMedications)
    }

    // MARK: - UC-11 Deletion Requests Persistence
    public func loadPersistedDeletionRequests() {
        self.pendingDeletionRequests = store.loadDeletionRequests()
    }

    private func persistDeletionRequests() {
        store.saveDeletionRequests(pendingDeletionRequests)
    }

    // MARK: - Dose Time Window Rules (Backed by DoseWindowConfig)
    public static var preDoseWindowMinutes: Int { DoseWindowConfig.preWindowMinutes }
    public static var lateThresholdMinutes: Int { DoseWindowConfig.lateThresholdMinutes }
    public static var missedCutoffMinutes: Int { DoseWindowConfig.missedCutoffMinutes }

    public enum DoseInteractionState: Equatable {
        case taken
        case upcomingBeforeWindow
        case dueOnTime
        case overdueLate
        case missed
    }

    /// Computes the exact scheduled `Date` for a dose slot (or primary dose time) of `item` on the calendar day of `dayDate`.
    public func scheduledDateTime(for item: MedicationItem, on dayDate: Date, slotMinutes: Int? = nil) -> Date {
        let calendar = Calendar.current
        let mins = slotMinutes ?? scheduledMinutes(for: item)
        return calendar.date(bySettingHour: mins / 60, minute: mins % 60, second: 0, of: dayDate) ?? dayDate
    }

    private func effectiveScheduleStart(for item: MedicationItem) -> Date {
        max(item.createdAt, item.scheduleUpdatedAt)
    }

    /// True when the specific dose slot (`slotMinutes`) has already been taken on `date`.
    public func isSlotTakenToday(_ item: MedicationItem, slotMinutes: Int, on date: Date) -> Bool {
        let calendar = Calendar.current
        if let slotTakenAt = item.takenSlotsToday[slotMinutes],
           calendar.isDate(slotTakenAt, inSameDayAs: date) {
            return true
        }
        if item.takenSlotsToday.isEmpty && slotMinutes == scheduledMinutes(for: item),
           item.isTaken,
           let takenAt = item.takenAt,
           calendar.isDate(takenAt, inSameDayAs: date) {
            return true
        }
        return adherenceService.hasTakenRecord(for: item.id, on: date, slotMinutes: slotMinutes)
    }

    private func hasActiveCarryoverFromYesterday(_ item: MedicationItem, slotMinutes: Int, at date: Date) -> Bool {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date),
              isScheduledForToday(item, on: yesterday) else {
            return false
        }
        let yesterdaySched = scheduledDateTime(for: item, on: yesterday, slotMinutes: slotMinutes)
        let scheduleStart = effectiveScheduleStart(for: item)
        let anchorMinuteStart = calendar.date(bySetting: .second, value: 0, of: scheduleStart) ?? scheduleStart
        if yesterdaySched < anchorMinuteStart {
            return false
        }
        guard !adherenceService.hasRecord(for: item.id, on: yesterday, slotMinutes: slotMinutes) else {
            return false
        }
        let diffYesterdayMin = Int(floor(date.timeIntervalSince(yesterdaySched) / 60.0))
        return diffYesterdayMin >= -DoseWindowConfig.preWindowMinutes && diffYesterdayMin < DoseWindowConfig.missedCutoffMinutes
    }

    /// Returns true when yesterday's scheduled dose (for any slot) was not yet recorded and its confirmation window extends past midnight into `date`.
    private func hasActiveCarryoverFromYesterday(_ item: MedicationItem, at date: Date) -> Bool {
        dailyDoseTimesMinutes(for: item).contains { slotMin in
            hasActiveCarryoverFromYesterday(item, slotMinutes: slotMin, at: date)
        }
    }

    /// Returns the active occurrence `Date` (yesterday carryover if still open past midnight, otherwise today's scheduled `Date`).
    private func activeOccurrenceDate(for item: MedicationItem, at date: Date) -> Date {
        let slots = dailyDoseTimesMinutes(for: item)
        if let carryoverSlot = slots.first(where: { hasActiveCarryoverFromYesterday(item, slotMinutes: $0, at: date) }),
           let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) {
            return scheduledDateTime(for: item, on: yesterday, slotMinutes: carryoverSlot)
        }
        let primary = slots.first ?? scheduledMinutes(for: item)
        return scheduledDateTime(for: item, on: date, slotMinutes: primary)
    }

    /// Evaluates the interaction state for a single scheduled dose slot (either today or yesterday midnight carryover).
    public func doseInteractionState(
        for item: MedicationItem,
        slotMinutes: Int,
        at date: Date? = nil,
        isCarryover: Bool = false
    ) -> DoseInteractionState {
        let effectiveDate = date ?? AppClock.shared.now
        let calendar = Calendar.current

        if isCarryover {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: effectiveDate) else {
                return .missed
            }
            if adherenceService.hasTakenRecord(for: item.id, on: yesterday, slotMinutes: slotMinutes) {
                return .taken
            }
            let yesterdaySched = scheduledDateTime(for: item, on: yesterday, slotMinutes: slotMinutes)
            let diffMin = Int(floor(effectiveDate.timeIntervalSince(yesterdaySched) / 60.0))
            if diffMin < -DoseWindowConfig.preWindowMinutes {
                return .upcomingBeforeWindow
            } else if diffMin < DoseWindowConfig.lateThresholdMinutes {
                return .dueOnTime
            } else if diffMin < DoseWindowConfig.missedCutoffMinutes {
                return .overdueLate
            } else {
                return .missed
            }
        }

        if isSlotTakenToday(item, slotMinutes: slotMinutes, on: effectiveDate) {
            return .taken
        }

        guard isScheduledForToday(item, on: effectiveDate) else {
            return .upcomingBeforeWindow
        }

        let todaySched = scheduledDateTime(for: item, on: effectiveDate, slotMinutes: slotMinutes)
        let scheduleStart = effectiveScheduleStart(for: item)
        let scheduleStartMinute = calendar.date(bySetting: .second, value: 0, of: scheduleStart) ?? scheduleStart
        if calendar.isDate(scheduleStart, inSameDayAs: effectiveDate) && todaySched < scheduleStartMinute {
            return .upcomingBeforeWindow
        }

        let diffMin = Int(floor(effectiveDate.timeIntervalSince(todaySched) / 60.0))
        if diffMin < -DoseWindowConfig.preWindowMinutes {
            return .upcomingBeforeWindow
        } else if diffMin < DoseWindowConfig.lateThresholdMinutes {
            return .dueOnTime
        } else if diffMin < DoseWindowConfig.missedCutoffMinutes {
            return .overdueLate
        } else {
            return .missed
        }
    }

    /// Evaluates the overall interaction state of a medication across its daily slots (and yesterday carryover).
    public func doseInteractionState(for item: MedicationItem, at date: Date? = nil) -> DoseInteractionState {
        let effectiveDate = date ?? AppClock.shared.now
        let slots = dailyDoseTimesMinutes(for: item)

        var slotStates: [DoseInteractionState] = []
        for slotMin in slots {
            if hasActiveCarryoverFromYesterday(item, slotMinutes: slotMin, at: effectiveDate) {
                slotStates.append(doseInteractionState(for: item, slotMinutes: slotMin, at: effectiveDate, isCarryover: true))
            }
            if isScheduledForToday(item, on: effectiveDate) {
                slotStates.append(doseInteractionState(for: item, slotMinutes: slotMin, at: effectiveDate, isCarryover: false))
            }
        }

        if slotStates.isEmpty {
            return .upcomingBeforeWindow
        }
        if slotStates.contains(.overdueLate) { return .overdueLate }
        if slotStates.contains(.dueOnTime) { return .dueOnTime }
        if slotStates.contains(.upcomingBeforeWindow) { return .upcomingBeforeWindow }
        if slotStates.allSatisfy({ $0 == .taken }) { return .taken }
        return .missed
    }

    /// Returns the number of minutes elapsed past the scheduled time when `item` (or specific slot) is currently `.overdueLate`, or `nil` otherwise.
    public func overdueMinutes(
        for item: MedicationItem,
        slotMinutes: Int? = nil,
        at date: Date? = nil,
        isCarryover: Bool = false
    ) -> Int? {
        let effectiveDate = date ?? AppClock.shared.now
        if let slotMinutes {
            guard doseInteractionState(for: item, slotMinutes: slotMinutes, at: effectiveDate, isCarryover: isCarryover) == .overdueLate else {
                return nil
            }
            let dayRef = isCarryover
                ? (Calendar.current.date(byAdding: .day, value: -1, to: effectiveDate) ?? effectiveDate)
                : effectiveDate
            let occurrence = scheduledDateTime(for: item, on: dayRef, slotMinutes: slotMinutes)
            let elapsed = Int(floor(effectiveDate.timeIntervalSince(occurrence) / 60.0))
            return max(elapsed, DoseWindowConfig.lateThresholdMinutes)
        }

        let slots = dailyDoseTimesMinutes(for: item)
        for slotMin in slots {
            if hasActiveCarryoverFromYesterday(item, slotMinutes: slotMin, at: effectiveDate),
               let mins = overdueMinutes(for: item, slotMinutes: slotMin, at: effectiveDate, isCarryover: true) {
                return mins
            }
            if isScheduledForToday(item, on: effectiveDate),
               let mins = overdueMinutes(for: item, slotMinutes: slotMin, at: effectiveDate, isCarryover: false) {
                return mins
            }
        }
        return nil
    }

    /// Reconciles taken flags from previous days, handles doses crossing midnight without losing their state,
    /// and retroactively marks any past unrecorded scheduled doses whose cutoff window has elapsed as `.missed`.
    /// Every dose record is written under the medication's own `patientId`.
    private func reconcilePastAndMidnightDoses(at now: Date) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)

        // 1. Preserve previous-day taken slots/flags in AdherenceService BEFORE resetting for the new day
        var didResetStaleDay = false
        var resetMedications: [MedicationItem] = []
        for idx in allMedications.indices {
            var itemChanged = false

            // Clear stale slot-level confirmations from previous days
            let staleSlots = allMedications[idx].takenSlotsToday.filter { !calendar.isDate($0.value, inSameDayAs: now) }
            for (slotMin, slotTakenAt) in staleSlots {
                if slotTakenAt <= now {
                    adherenceService.recordDoseTaken(
                        medication: allMedications[idx],
                        patientId: allMedications[idx].patientId,
                        takenAt: slotTakenAt,
                        scheduledDay: slotTakenAt,
                        slotMinutes: slotMin
                    )
                }
                allMedications[idx].takenSlotsToday.removeValue(forKey: slotMin)
                itemChanged = true
            }

            // Handle legacy items where `isTaken` was persisted without `takenSlotsToday`
            if allMedications[idx].isTaken && allMedications[idx].takenSlotsToday.isEmpty {
                let primarySlot = scheduledMinutes(for: allMedications[idx])
                if let takenAt = allMedications[idx].takenAt {
                    if !calendar.isDate(takenAt, inSameDayAs: now) {
                        if takenAt <= now {
                            adherenceService.recordDoseTaken(
                                medication: allMedications[idx],
                                patientId: allMedications[idx].patientId,
                                takenAt: takenAt,
                                scheduledDay: takenAt,
                                slotMinutes: primarySlot
                            )
                        }
                        allMedications[idx].isTaken = false
                        allMedications[idx].takenAt = nil
                        itemChanged = true
                    }
                } else if !adherenceService.hasTakenRecord(for: allMedications[idx].id, on: now, slotMinutes: primarySlot) {
                    allMedications[idx].isTaken = false
                    allMedications[idx].takenAt = nil
                    itemChanged = true
                }
            }

            if itemChanged {
                let slots = dailyDoseTimesMinutes(for: allMedications[idx])
                allMedications[idx].isTaken = !slots.isEmpty && slots.allSatisfy {
                    isSlotTakenToday(allMedications[idx], slotMinutes: $0, on: now)
                }
                if allMedications[idx].takenSlotsToday.isEmpty && !allMedications[idx].isTaken {
                    allMedications[idx].takenAt = nil
                }
                didResetStaleDay = true
                resetMedications.append(allMedications[idx])
            }
        }
        if didResetStaleDay {
            persistMedications()
            // Re-arm missed-dose alerts for the new day.
            let toReschedule = resetMedications
            Task {
                for med in toReschedule {
                    await self.scheduleMissedDoseAlert(for: med)
                }
            }
        }

        // 2. Retroactive backfill for past days across every scheduled daily slot
        for med in allMedications {
            let scheduleStart = effectiveScheduleStart(for: med)
            let anchorDay = calendar.startOfDay(for: scheduleStart)
            let earliestLookback = calendar.date(byAdding: .day, value: -DoseWindowConfig.retroactiveLookbackDays, to: todayStart) ?? anchorDay
            var day = max(anchorDay, earliestLookback)
            let anchorMinuteStart = calendar.date(bySetting: .second, value: 0, of: scheduleStart) ?? scheduleStart
            let slots = dailyDoseTimesMinutes(for: med)

            while day < todayStart {
                if isScheduledForToday(med, on: day) {
                    for slotMin in slots {
                        let schedDate = scheduledDateTime(for: med, on: day, slotMinutes: slotMin)
                        let isBeforeScheduleStart = calendar.isDate(day, inSameDayAs: scheduleStart) && schedDate < anchorMinuteStart
                        if !isBeforeScheduleStart {
                            let elapsedMinutes = Int(floor(now.timeIntervalSince(schedDate) / 60.0))
                            // If a midnight-crossing dose (e.g. 23:00 checked at 00:30) is still within 120m, keep it open rather than marking missed
                            if elapsedMinutes >= DoseWindowConfig.missedCutoffMinutes && !adherenceService.hasRecord(for: med.id, on: day, slotMinutes: slotMin) {
                                adherenceService.recordDoseMissedIfNeeded(
                                    medication: med,
                                    patientId: med.patientId,
                                    on: day,
                                    slotMinutes: slotMin
                                )
                            }
                        }
                    }
                }
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
            }
        }
    }

    // MARK: - Per-Patient Day Schedule
    /// Today's schedule for one patient, derived only from that patient's medications and daily dose slots.
    public struct PatientDaySchedule: Equatable {
        public let patientId: String
        /// All dose occurrences scheduled today (plus open yesterday carryovers), sorted chronologically.
        public let todayDoses: [ScheduledDose]
        /// All currently active/highlighted dose occurrences shown under "ادويتي".
        public let activeDoses: [ScheduledDose]
        /// Dose occurrences currently overdue (>=30m late) or missed today.
        public let missedDoses: [ScheduledDose]
        /// Medications scheduled today (or still open from yesterday past midnight), sorted chronologically.
        public let todayMedications: [MedicationItem]
        public let activeMedications: [MedicationItem]
        public var activeMedication: MedicationItem? { activeMedications.first }
        public let upcomingDoses: [UpcomingDose]
        /// Untaken dose occurrences that can still be confirmed today (excludes taken and missed doses).
        public let remainingDoses: Int
        /// Today's medications having an unconfirmed dose past `DoseWindowConfig.lateThresholdMinutes`.
        public let missedMedications: [MedicationItem]

        public var hasMissedDoses: Bool { !missedDoses.isEmpty }
    }

    private func uniqueMedicationsPreservingOrder(from doses: [ScheduledDose]) -> [MedicationItem] {
        var seen = Set<UUID>()
        var result: [MedicationItem] = []
        for dose in doses where seen.insert(dose.medication.id).inserted {
            result.append(dose.medication)
        }
        return result
    }

    /// UC-12 S#1, S#2, S#3: computes `patientId`'s schedule for the day containing `date`. Has no side effects.
    public func daySchedule(forPatient patientId: String, at date: Date? = nil) -> PatientDaySchedule {
        let now = date ?? AppClock.shared.now
        let calendar = Calendar.current

        // 1. Expand each patient medication into daily dose occurrences (plus any active carryover from yesterday)
        let patientMeds = allMedications.filter { $0.patientId == patientId }
        var allDoses: [ScheduledDose] = []

        for med in patientMeds {
            let slots = dailyDoseTimesMinutes(for: med)
            let isScheduledToday = isScheduledForToday(med, on: now)
            let scheduleStart = effectiveScheduleStart(for: med)
            let isCreatedToday = calendar.isDate(scheduleStart, inSameDayAs: now)
            let anchorMinuteStart = calendar.date(bySetting: .second, value: 0, of: scheduleStart) ?? scheduleStart
            let hasFutureOrCurrentSlotOnCreationDay = isCreatedToday && slots.contains {
                scheduledDateTime(for: med, on: now, slotMinutes: $0) >= anchorMinuteStart
            }

            for slotMin in slots {
                if hasActiveCarryoverFromYesterday(med, slotMinutes: slotMin, at: now),
                   let yesterday = calendar.date(byAdding: .day, value: -1, to: now) {
                    let occ = scheduledDateTime(for: med, on: yesterday, slotMinutes: slotMin)
                    allDoses.append(
                        ScheduledDose(
                            medication: med,
                            slotMinutes: slotMin,
                            occurrenceDate: occ,
                            timeString: formattedTimeString(forSlotMinutes: slotMin),
                            isCarryoverFromYesterday: true
                        )
                    )
                }

                if isScheduledToday {
                    let occ = scheduledDateTime(for: med, on: now, slotMinutes: slotMin)
                    // When multiple doses per day are scheduled and at least one slot is still ahead today,
                    // omit slots earlier than creation time on the first day so they don't appear before upcoming doses.
                    if isCreatedToday && slots.count > 1 && hasFutureOrCurrentSlotOnCreationDay && occ < anchorMinuteStart {
                        continue
                    }
                    allDoses.append(
                        ScheduledDose(
                            medication: med,
                            slotMinutes: slotMin,
                            occurrenceDate: occ,
                            timeString: formattedTimeString(forSlotMinutes: slotMin),
                            isCarryoverFromYesterday: false
                        )
                    )
                }
            }
        }

        // 2. Sort daily dose occurrences chronologically
        let sortedDoses = allDoses.sorted { a, b in
            if a.occurrenceDate != b.occurrenceDate {
                return a.occurrenceDate < b.occurrenceDate
            }
            return a.medication.name < b.medication.name
        }

        let stateOf: (ScheduledDose) -> DoseInteractionState = { dose in
            self.doseInteractionState(
                for: dose.medication,
                slotMinutes: dose.slotMinutes,
                at: now,
                isCarryover: dose.isCarryoverFromYesterday
            )
        }

        // 3. Prioritize confirmable or upcoming dose occurrences (excluding taken and missed doses)
        let actionableUntaken = sortedDoses.filter { dose in
            let state = stateOf(dose)
            return state == .dueOnTime || state == .overdueLate || state == .upcomingBeforeWindow
        }

        let activeDoseList: [ScheduledDose]
        if !actionableUntaken.isEmpty {
            let confirmableNow = actionableUntaken.filter { dose in
                let state = stateOf(dose)
                return state == .dueOnTime || state == .overdueLate
            }
            let futureToday = actionableUntaken.filter { dose in
                stateOf(dose) == .upcomingBeforeWindow
            }

            if !confirmableNow.isEmpty {
                // Include all currently confirmable doses: overdue first (chronologically), then due on time.
                let overdueNow = confirmableNow.filter { stateOf($0) == .overdueLate }
                let dueNow = confirmableNow.filter { stateOf($0) == .dueOnTime }
                activeDoseList = overdueNow + dueNow
            } else if let earliestDate = futureToday.first?.occurrenceDate {
                // Include all upcoming doses sharing the exact earliest scheduled date/time.
                activeDoseList = futureToday.filter { $0.occurrenceDate == earliestDate }
            } else {
                activeDoseList = Array(actionableUntaken.prefix(1))
            }
        } else {
            if let fallback = sortedDoses.last ?? sortedDoses.first {
                activeDoseList = [fallback]
            } else {
                activeDoseList = []
            }
        }

        // 4. Generate schedule rows for other doses today (excluding active cards)
        let activeDoseIds = Set(activeDoseList.map(\.id))
        let upcoming = sortedDoses
            .filter { !activeDoseIds.contains($0.id) }
            .map { dose in
                let slotsCount = dailyDoseTimesMinutes(for: dose.medication).count
                let rowId = (slotsCount == 1 && !dose.isCarryoverFromYesterday) ? dose.medication.id : UUID()
                return UpcomingDose(
                    id: rowId,
                    medicationId: dose.medication.id,
                    slotMinutes: dose.slotMinutes,
                    name: dose.medication.name,
                    timeString: dose.timeString,
                    dosage: dose.medication.dosage.westernNumerals,
                    isTaken: stateOf(dose) == .taken,
                    imageData: dose.medication.imageData
                )
            }

        let missedDoses = sortedDoses.filter { dose in
            let s = stateOf(dose)
            return s == .overdueLate || s == .missed
        }

        return PatientDaySchedule(
            patientId: patientId,
            todayDoses: sortedDoses,
            activeDoses: activeDoseList,
            missedDoses: missedDoses,
            todayMedications: uniqueMedicationsPreservingOrder(from: sortedDoses),
            activeMedications: uniqueMedicationsPreservingOrder(from: activeDoseList),
            upcomingDoses: upcoming,
            remainingDoses: actionableUntaken.count,
            missedMedications: uniqueMedicationsPreservingOrder(from: missedDoses)
        )
    }

    private func reconcileMissedDosesForToday(at now: Date) {
        let calendar = Calendar.current
        for item in allMedications where isScheduledForToday(item, on: now) {
            let scheduleStart = effectiveScheduleStart(for: item)
            let startMinute = calendar.date(bySetting: .second, value: 0, of: scheduleStart) ?? scheduleStart
            let slots = dailyDoseTimesMinutes(for: item)
            for slotMin in slots {
                let schedToday = scheduledDateTime(for: item, on: now, slotMinutes: slotMin)
                let startsAtOrAfterAnchor = schedToday >= startMinute || !calendar.isDate(scheduleStart, inSameDayAs: now)
                if startsAtOrAfterAnchor && doseInteractionState(for: item, slotMinutes: slotMin, at: now) == .missed {
                    adherenceService.recordDoseMissedIfNeeded(
                        medication: item,
                        patientId: item.patientId,
                        on: now,
                        slotMinutes: slotMin
                    )
                }
            }
        }
    }

    // MARK: - UC-12 S#1, S#2, S#3: Automatically Sort & Prioritize by Scheduled Time
    public func refreshDerivedState(at overrideNow: Date? = nil) {
        let now = overrideNow ?? AppClock.shared.now
        let patientId = MedicationItem.currentIdentityPatientId

        // Reconcile day rollover, midnight carryover, and past unrecorded missed doses before evaluating today
        reconcilePastAndMidnightDoses(at: now)

        // Automatically record any dose today that crossed the missed cutoff as `.missed` ("فائتة") in AdherenceService,
        // for every patient whose medications are stored on this device.
        reconcileMissedDosesForToday(at: now)

        // Published state describes only the patient using this device
        let schedule = daySchedule(forPatient: patientId, at: now)
        self.currentPatientId = patientId
        self.medications = medicationList(forPatient: patientId)
        self.todayDoses = schedule.todayDoses
        self.activeDoses = schedule.activeDoses
        self.todayMedications = schedule.todayMedications
        self.activeMedications = schedule.activeMedications
        self.activeMedication = schedule.activeMedication
        self.upcomingDoses = schedule.upcomingDoses
        self.remainingDoses = schedule.remainingDoses
        self.lastEvaluatedAt = now

        if schedulesSystemNotifications {
            DoseLiveActivityManager.shared.sync(using: self, at: now)
        }
    }

    // MARK: - Use-Case 5 (UC-5): Missed Dose Calculations (30-Minute Grace Period)
    /// UC-5 S#1: Determines if a scheduled dose has remained unconfirmed past `DoseWindowConfig.lateThresholdMinutes`
    public func isDoseMissed(_ item: MedicationItem, at date: Date? = nil) -> Bool {
        let effectiveDate = date ?? AppClock.shared.now
        let state = doseInteractionState(for: item, at: effectiveDate)
        return state == .overdueLate || state == .missed
    }

    /// The current patient's medications scheduled for today whose late threshold has passed without confirmation
    public var missedMedicationsToday: [MedicationItem] {
        let now = AppClock.shared.now
        return todayMedications.filter { isDoseMissed($0, at: now) }
    }

    /// The current patient's medications scheduled for today that are currently late (`.overdueLate`) and still confirmable
    public var overdueLateMedicationsToday: [MedicationItem] {
        let now = AppClock.shared.now
        return todayMedications.filter { doseInteractionState(for: $0, at: now) == .overdueLate }
    }

    /// True when any of the current patient's medications has remained unconfirmed 30 minutes past its due time
    public var hasMissedDosesToday: Bool {
        !missedMedicationsToday.isEmpty
    }

    // MARK: - UC-12 Helper Functions (Schedule Day & Time Calculations)

    /// Returns sorted Gregorian weekday numbers (1 = Sunday ... 7 = Saturday) when specific days are chosen,
    /// or `nil` when the medication repeats every day.
    /// Reads the structured `item.selectedWeekdays` first, falling back to parsing legacy `item.days` strings if needed.
    public func scheduledWeekdays(for item: MedicationItem) -> [Int]? {
        let structured = Set(item.selectedWeekdays.filter { (1...7).contains($0) })
        if !structured.isEmpty {
            return structured.count == 7 ? nil : structured.sorted()
        }
        let parsed = MedicationWeekday.parseWeekdayNumbers(from: item.days)
        return parsed.isEmpty ? nil : parsed.sorted()
    }

    private func dayInterval(for frequency: String) -> Int? {
        let clean = frequency.westernNumerals.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains("يومين") { return 2 }
        if clean.contains("3 أيام") || clean.contains("3 ايام") || clean.contains("ثلاثة أيام") || clean.contains("ثلاثة ايام") {
            return 3
        }
        if clean.contains("أسبوع") || clean.contains("اسبوع") { return 7 }
        return nil
    }

    private func parsedHourlyInterval(from frequency: String) -> Int? {
        let clean = frequency.westernNumerals.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.contains("ساعة") || clean.contains("ساعات") else { return nil }
        let digits = clean.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        if let hours = Int(digits), hours >= 1, hours < 24 {
            return hours
        }
        return nil
    }

    private func parsedTimesPerDay(from frequency: String) -> Int? {
        let clean = frequency.westernNumerals.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains("مرتان") || clean.contains("مرتين") { return 2 }
        if clean.contains("ثلاث مرات") { return 3 }
        if clean.contains("أربع مرات") || clean.contains("اربع مرات") { return 4 }
        if clean.contains("مرة يوم") || clean == "مرة واحدة" { return 1 }
        if clean.contains("مرات") {
            let digits = clean.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            if let count = Int(digits), count >= 2, count <= 6 {
                return count
            }
        }
        return nil
    }

    /// Returns sorted unique scheduled times of day in minutes from midnight (0..<1440) derived from `item`'s structured times or legacy frequency.
    public func dailyDoseTimesMinutes(for item: MedicationItem) -> [Int] {
        // 1. As needed medications do not have daily dose scheduled times
        if item.scheduleType == .asNeeded {
            return []
        }

        // 2. If user specifically configured custom dose times, return them
        if !item.customDoseTimesMinutes.isEmpty {
            return item.customDoseTimesMinutes.sorted()
        }

        let start = ((scheduledMinutes(for: item) % 1440) + 1440) % 1440

        if let hours = parsedHourlyInterval(from: item.frequency) {
            let step = hours * 60
            var slots = Set<Int>()
            if 24 % hours == 0 {
                let count = 24 / hours
                for k in 0..<count {
                    slots.insert((start + k * step) % 1440)
                }
            } else {
                var current = start
                while current < 1440 && slots.count < 12 {
                    slots.insert(current)
                    current += step
                }
            }
            return slots.sorted()
        }

        if let count = parsedTimesPerDay(from: item.frequency), count > 1 {
            let step = 1440 / count
            var slots = Set<Int>()
            for k in 0..<count {
                slots.insert((start + k * step) % 1440)
            }
            return slots.sorted()
        }

        return [start]
    }

    /// Formats a minute-of-day value (0..<1440) using Western digits and Arabic AM/PM ("08:00 ص" / "08:00 م").
    public func formattedTimeString(forSlotMinutes minutes: Int) -> String {
        let normalized = ((minutes % 1440) + 1440) % 1440
        let hour24 = normalized / 60
        let minute = normalized % 60
        let period = hour24 >= 12 ? "م" : "ص"
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 }
        return String(format: "%02d:%02d %@", locale: Locale(identifier: "en_US_POSIX"), hour12, minute, period).westernNumerals
    }

    /// UC-12 S#1: Identifies medications scheduled for the current day
    public func isScheduledForToday(_ item: MedicationItem, on date: Date = Date()) -> Bool {
        // 1. As-needed medications have no recurring scheduled day
        if item.scheduleType == .asNeeded {
            return false
        }

        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)

        // 2. Check endDate (reminders stop after last day)
        if let endDate = item.endDate {
            let endDay = calendar.startOfDay(for: endDate)
            if targetDay > endDay {
                return false
            }
        }

        // 3. Check startDate (cannot be scheduled before start date)
        let anchorDay = calendar.startOfDay(for: effectiveScheduleStart(for: item))
        if targetDay < anchorDay {
            return false
        }

        // 4. Check schedule type: every other day
        if item.scheduleType == .everyOtherDay {
            let diff = calendar.dateComponents([.day], from: anchorDay, to: targetDay).day ?? 0
            return diff >= 0 && diff % 2 == 0
        }

        // 5. Check schedule type: specific weekdays
        if item.scheduleType == .specificWeekdays || !item.selectedWeekdays.isEmpty {
            let weekdays: Set<Int> = item.selectedWeekdays.isEmpty
                ? Set(scheduledWeekdays(for: item) ?? [])
                : item.selectedWeekdays
            let weekday = calendar.component(.weekday, from: date)
            return weekdays.contains(weekday)
        }

        // 6. Legacy frequency intervals check
        if let weekdays = scheduledWeekdays(for: item) {
            let weekday = calendar.component(.weekday, from: date)
            return weekdays.contains(weekday)
        }
        if let interval = dayInterval(for: item.frequency) {
            let diff = calendar.dateComponents([.day], from: anchorDay, to: targetDay).day ?? 0
            return diff >= 0 && diff % interval == 0
        }
        if item.frequency.contains("شهري") {
            let anchorDayNum = calendar.component(.day, from: effectiveScheduleStart(for: item))
            let targetDayNum = calendar.component(.day, from: date)
            return anchorDayNum == targetDayNum
        }

        return true
    }

    /// Converts scheduled time into minutes from midnight (0 ..< 1440) for precise chronological sorting
    public func scheduledMinutes(for item: MedicationItem) -> Int {
        if let date = item.scheduledDate {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }
        return parseTimeToMinutes(item.timeString)
    }

    private func parseTimeToMinutes(_ timeStr: String) -> Int {
        let clean = timeStr.westernNumerals.trimmingCharacters(in: .whitespaces)
        let isPM = clean.contains("م") || clean.lowercased().contains("pm")
        let isAM = clean.contains("ص") || clean.lowercased().contains("am")

        let digits = clean.replacingOccurrences(of: "[^0-9:]", with: "", options: .regularExpression)
        let parts = digits.split(separator: ":")
        guard let hStr = parts.first, let h = Int(hStr) else { return 12 * 60 }
        let m = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0

        var hour = h
        if isPM && hour < 12 {
            hour += 12
        } else if isAM && hour == 12 {
            hour = 0
        }
        return hour * 60 + m
    }

    // MARK: - UC-3 S#2 & S#4: Add Medication
    public func addMedication(
        item: MedicationItem,
        currentUser: UserIdentity,
        targetPatientId: String? = nil
    ) async throws {
        var cleanItem = item
        cleanItem.timeString = cleanItem.timeString.westernNumerals
        cleanItem.dosage = cleanItem.dosage.westernNumerals

        // 1. Validation: Required fields (UC-3 Alternate Course S#1)
        try validateRequiredFields(name: cleanItem.name, dosage: cleanItem.dosage, timeString: cleanItem.timeString)

        // 2. Validation & Normalization: Image size (UC-3 Alternate Course S#4)
        if let imgData = cleanItem.imageData {
            if let uiImage = UIImage(data: imgData),
               imgData.count > 900_000,
               let compressed = Self.compressAndNormalizeImage(uiImage) {
                cleanItem.imageData = compressed.data
            }
            if let finalData = cleanItem.imageData {
                try validateImageData(finalData)
            }
        }

        // 3. Authorization check for Caregiver (UC-3 Alternate Course S#8) and ownership:
        // a caregiver adds to a linked patient's schedule, a patient adds to their own.
        if currentUser.role == .caregiver {
            try validateCaregiverPermission(caregiverId: currentUser.id, targetPatientId: targetPatientId)
            guard let targetPatientId else { throw MedicationError.unauthorizedCaregiver }
            cleanItem.patientId = targetPatientId
        } else {
            cleanItem.patientId = currentUser.id
        }

        // 4. Prevent duplicate medication record with same name and time for the same patient
        let duplicate = allMedications.contains { existing in
            existing.patientId == cleanItem.patientId &&
            existing.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ==
                cleanItem.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() &&
            existing.timeString == cleanItem.timeString
        }
        if duplicate {
            // Avoid duplicate additions
            showToast("الدواء مسجل بالفعل بنفس الموعد.")
            return
        }

        // 5. Save to database / local store (UC-3 S#5)
        allMedications.insert(cleanItem, at: 0)
        persistMedications()
        refreshDerivedState()
        CloudKitSyncManager.shared.publishMedication(cleanItem)

        // 6. Schedule Notification Reminder (UC-3 S#6 & Alternate Course S#9)
        let scheduled = await scheduleReminder(for: cleanItem)
        if !scheduled {
            self.notificationWarning = "تم حفظ الدواء بنجاح، ولكن تعذر تفعيل التذكيرات (يرجى التحقق من أذونات الإشعارات في الإعدادات)."
        }

        // 7. Success confirmation message (UC-3 S#8)
        if currentUser.role == .caregiver {
            showToast("تمت إضافة دواء \"\(cleanItem.name)\" بنجاح في جدول المستفيد!")
        } else if !relationshipService.activeRelationships.isEmpty {
            showToast("تمت إضافة دواء \"\(cleanItem.name)\" بنجاح وجدولة التذكيرات!")
            // Instantly notify caregiver
            relationshipService.showToast("🔔 قام \(currentUser.displayName) بإضافة دواء جديد: \"\(cleanItem.name)\" (\(cleanItem.timeString))")
        } else {
            showToast("تمت إضافة دواء \"\(cleanItem.name)\" بنجاح وجدولة التذكيرات!")
        }
    }

    // MARK: - Update Existing Medication (Edit Mode)
    public func updateMedication(
        item: MedicationItem,
        currentUser: UserIdentity? = nil,
        targetPatientId: String? = nil
    ) async throws {
        var cleanItem = item
        cleanItem.timeString = cleanItem.timeString.westernNumerals
        cleanItem.dosage = cleanItem.dosage.westernNumerals

        // 1. Validation
        try validateRequiredFields(name: cleanItem.name, dosage: cleanItem.dosage, timeString: cleanItem.timeString)

        if let imgData = cleanItem.imageData {
            if let uiImage = UIImage(data: imgData),
               imgData.count > 900_000,
               let compressed = Self.compressAndNormalizeImage(uiImage) {
                cleanItem.imageData = compressed.data
            }
            if let finalData = cleanItem.imageData {
                try validateImageData(finalData)
            }
        }

        guard let index = allMedications.firstIndex(where: { $0.id == cleanItem.id }) else {
            throw MedicationError.saveFailed
        }

        // Ownership never changes on edit; a caregiver must be linked to the medication's owner.
        let existingMed = allMedications[index]
        let ownerId = existingMed.patientId
        cleanItem.patientId = ownerId
        if let user = currentUser, user.role == .caregiver {
            if let targetPatientId, targetPatientId != ownerId {
                throw MedicationError.unauthorizedCaregiver
            }
            try validateCaregiverPermission(caregiverId: user.id, targetPatientId: ownerId)
        }

        let now = AppClock.shared.now
        let calendar = Calendar.current
        let timeChanged = existingMed.timeString != cleanItem.timeString
        let frequencyChanged = existingMed.frequency != cleanItem.frequency
        let scheduleChanged =
            timeChanged ||
            frequencyChanged ||
            existingMed.days != cleanItem.days ||
            existingMed.selectedWeekdays != cleanItem.selectedWeekdays

        if scheduleChanged {
            // 1. Reconcile past, midnight, and today missed doses using the OLD schedule first so unrecorded missed doses are not lost
            reconcilePastAndMidnightDoses(at: now)
            reconcileMissedDosesForToday(at: now)
            if timeChanged || frequencyChanged || !isScheduledForToday(existingMed, on: now) {
                cleanItem.scheduleUpdatedAt = now
            } else {
                cleanItem.scheduleUpdatedAt = existingMed.scheduleUpdatedAt
            }
        } else {
            cleanItem.scheduleUpdatedAt = existingMed.scheduleUpdatedAt
        }

        // 2. Preserve slots already confirmed today when compatible with the updated schedule
        let latestExistingMed = allMedications[index]
        let newSlots = Set(dailyDoseTimesMinutes(for: cleanItem))
        var preservedSlots: [Int: Date] = [:]
        for (slotMin, takenAt) in latestExistingMed.takenSlotsToday
        where newSlots.contains(slotMin) && calendar.isDate(takenAt, inSameDayAs: now) {
            preservedSlots[slotMin] = takenAt
        }
        if preservedSlots.isEmpty && latestExistingMed.isTaken {
            let primarySlot = scheduledMinutes(for: cleanItem)
            if newSlots.contains(primarySlot) {
                if let takenAt = latestExistingMed.takenAt, calendar.isDate(takenAt, inSameDayAs: now) {
                    preservedSlots[primarySlot] = takenAt
                } else if adherenceService.hasTakenRecord(for: latestExistingMed.id, on: now, slotMinutes: primarySlot) {
                    preservedSlots[primarySlot] = now
                }
            }
        }
        cleanItem.takenSlotsToday = preservedSlots
        cleanItem.takenAt = preservedSlots.values.max()
        cleanItem.isTaken = !newSlots.isEmpty && newSlots.allSatisfy { preservedSlots[$0] != nil }

        allMedications[index] = cleanItem
        persistMedications()
        refreshDerivedState()
        CloudKitSyncManager.shared.publishMedication(cleanItem)

        // Reschedule reminder
        _ = await scheduleReminder(for: cleanItem)

        if let user = currentUser {
            if user.role == .caregiver {
                showToast("تم حفظ تعديلات دواء \"\(cleanItem.name)\" وتحديثها في جدول المستفيد.")
            } else if !relationshipService.activeRelationships.isEmpty {
                showToast("تم حفظ تعديلات دواء \"\(cleanItem.name)\" بنجاح وتحديث جدولك.")
                // Instantly notify caregiver
                relationshipService.showToast("🔔 قام \(user.displayName) بتعديل دواء \"\(cleanItem.name)\" (\(cleanItem.dosage) • \(cleanItem.timeString))")
            } else {
                showToast("تم حفظ تعديلات دواء \"\(cleanItem.name)\" بنجاح.")
            }
        } else {
            showToast("تم حفظ تعديلات دواء \"\(cleanItem.name)\" بنجاح.")
        }
    }

    // MARK: - Use-Case 11 (UC-11): Delete Medication
    /// Direct permanent deletion (when no caregiver is connected or when requested directly)
    public func deleteMedicationDirectly(id: UUID) {
        let now = AppClock.shared.now
        reconcilePastAndMidnightDoses(at: now)
        reconcileMissedDosesForToday(at: now)
        if let item = allMedications.first(where: { $0.id == id }) {
            // UC-11 S#5: Cancel future scheduled reminders
            cancelReminder(id: id)
            // UC-11 S#4: Remove medication from active medication list and update system database
            let removedRequests = pendingDeletionRequests.filter { $0.medicationId == id }
            allMedications.removeAll(where: { $0.id == id })
            pendingDeletionRequests.removeAll(where: { $0.medicationId == id })
            persistMedications()
            persistDeletionRequests()
            CloudKitSyncManager.shared.publishMedicationDeletion(medicationId: id, patientId: item.patientId)
            for req in removedRequests {
                CloudKitSyncManager.shared.publishDeletionRequestRemoval(requestId: req.id, patientId: req.patientId)
            }
            // UC-11 S#6: Refresh medication list and Home Page to reflect deletion
            refreshDerivedState()
            showToast("تم حذف دواء \"\(item.name)\" بنجاح.")
        }
    }

    /// Legacy alias for direct deletion
    public func deleteMedication(id: UUID) {
        deleteMedicationDirectly(id: id)
    }

    /// UC-11: Caregiver deletes a medication directly
    /// Removes it permanently from the patient's schedule, cancels reminders, and updates views immediately.
    public func deleteMedicationByCaregiver(id: UUID, patientName: String? = nil) {
        let now = AppClock.shared.now
        reconcilePastAndMidnightDoses(at: now)
        reconcileMissedDosesForToday(at: now)
        guard let item = allMedications.first(where: { $0.id == id }) else { return }
        // UC-11 S#5: Cancels the medication's future scheduled reminders
        cancelReminder(id: id)
        // UC-11 S#4: Removes the medication from active medication list
        let removedRequests = pendingDeletionRequests.filter { $0.medicationId == id }
        allMedications.removeAll(where: { $0.id == id })
        pendingDeletionRequests.removeAll(where: { $0.medicationId == id })
        persistMedications()
        persistDeletionRequests()
        CloudKitSyncManager.shared.publishMedicationDeletion(medicationId: id, patientId: item.patientId)
        for req in removedRequests {
            CloudKitSyncManager.shared.publishDeletionRequestRemoval(requestId: req.id, patientId: req.patientId)
        }
        // UC-11 S#6: Refreshes medication list and Home Page
        refreshDerivedState()

        let target = patientName != nil ? " من جدول \(patientName!)" : ""
        showToast("تم حذف دواء \"\(item.name)\"\(target) نهائياً وإلغاء جميع التذكيرات.")
    }

    /// UC-11 Collaborative Workflow: Patient requests deletion of a medication
    /// If connected to caregivers: marks medication as pending deletion and sends one request to every caregiver
    /// linked to this patient. Any one of them can approve or reject it.
    /// If not connected to any caregiver: deletes directly.
    /// - Parameter caregivers: Relationships to consider; only active links to `patient` are used.
    public func requestMedicationDeletionByPatient(
        medicationId: UUID,
        patient: UserIdentity,
        caregivers: [ActiveRelationship]
    ) {
        guard let item = allMedications.first(where: { $0.id == medicationId && $0.patientId == patient.id }) else { return }

        var caregiverIds: [String] = []
        for rel in caregivers where rel.patientId == patient.id && rel.isActive && !caregiverIds.contains(rel.caregiverId) {
            caregiverIds.append(rel.caregiverId)
        }

        // If no caregiver is connected, delete directly
        if caregiverIds.isEmpty {
            deleteMedicationDirectly(id: medicationId)
            return
        }

        // Mark medication as pending deletion
        if let index = allMedications.firstIndex(where: { $0.id == medicationId }) {
            allMedications[index].isPendingDeletion = true
            persistMedications()
            refreshDerivedState()
            CloudKitSyncManager.shared.publishMedication(allMedications[index])
        }

        let activeRequest: MedicationDeletionRequest
        if let existingIndex = pendingDeletionRequests.firstIndex(where: { $0.medicationId == medicationId }) {
            // Already requested: make sure every currently linked caregiver can act on it
            pendingDeletionRequests[existingIndex].caregiverIds = caregiverIds
            activeRequest = pendingDeletionRequests[existingIndex]
        } else {
            let newRequest = MedicationDeletionRequest(
                medicationId: medicationId,
                medicationName: item.name,
                dosage: item.dosage,
                timeString: item.timeString,
                patientId: patient.id,
                patientDisplayName: patient.displayName,
                caregiverIds: caregiverIds
            )
            pendingDeletionRequests.append(newRequest)
            activeRequest = newRequest
        }
        persistDeletionRequests()
        CloudKitSyncManager.shared.publishDeletionRequest(activeRequest)

        if caregiverIds.count > 1 {
            showToast("تم إرسال طلب حذف دواء \"\(item.name)\" إلى مقدمي الرعاية المرتبطين بك للموافقة.")
        } else {
            showToast("تم إرسال طلب حذف دواء \"\(item.name)\" إلى مقدم الرعاية للموافقة.")
        }
    }

    /// True when `caregiverId` may approve or reject `request`: it was sent to them and they are still
    /// actively linked to the patient. Requests saved without recipients accept any linked caregiver.
    public func canRespond(to request: MedicationDeletionRequest, caregiverId: String) -> Bool {
        let isLinked = relationshipService.activeRelationships.contains {
            $0.caregiverId == caregiverId && $0.patientId == request.patientId && $0.isActive
        }
        guard isLinked else { return false }
        return request.caregiverIds.isEmpty || request.caregiverIds.contains(caregiverId)
    }

    /// Pending deletion requests that `caregiverId` can approve or reject.
    public func deletionRequests(forCaregiver caregiverId: String) -> [MedicationDeletionRequest] {
        pendingDeletionRequests.filter { canRespond(to: $0, caregiverId: caregiverId) }
    }

    /// Called after a patient–caregiver link ends. That caregiver is removed from the patient's pending
    /// deletion requests; a request left with no linked caregiver is withdrawn and its medication stays scheduled.
    /// If this device belongs to the caregiver whose link ended, wipe cached medications of this patient.
    public func relationshipEnded(patientId: String, caregiverId: String) {
        let currentIdentity = KeychainService.shared.loadUserIdentity()
        if currentIdentity?.role == .caregiver, currentIdentity?.id == caregiverId {
            allMedications.removeAll { $0.patientId == patientId }
            pendingDeletionRequests.removeAll { $0.patientId == patientId }
            persistMedications()
            persistDeletionRequests()
            refreshDerivedState()
            return
        }

        let stillLinked = Set(
            relationshipService.activeRelationships
                .filter { $0.patientId == patientId && $0.isActive }
                .map(\.caregiverId)
        )

        var withdrawnMedicationIds: [UUID] = []
        var changed = false
        for idx in pendingDeletionRequests.indices.reversed() where pendingDeletionRequests[idx].patientId == patientId {
            let original = pendingDeletionRequests[idx].caregiverIds
            let remaining = original.filter { $0 != caregiverId }
            // Requests saved without recipients stay open while any caregiver is still linked.
            let hasRecipient = original.isEmpty
                ? !stillLinked.isEmpty
                : remaining.contains { stillLinked.contains($0) }
            if hasRecipient {
                if remaining != pendingDeletionRequests[idx].caregiverIds {
                    pendingDeletionRequests[idx].caregiverIds = remaining
                    changed = true
                }
            } else {
                withdrawnMedicationIds.append(pendingDeletionRequests[idx].medicationId)
                pendingDeletionRequests.remove(at: idx)
                changed = true
            }
        }
        guard changed else { return }

        for idx in allMedications.indices where withdrawnMedicationIds.contains(allMedications[idx].id) {
            allMedications[idx].isPendingDeletion = false
        }
        if !withdrawnMedicationIds.isEmpty {
            persistMedications()
            refreshDerivedState()
        }
        persistDeletionRequests()
    }

    /// UC-11: Caregiver approves deletion request -> permanently deletes medication from patient's schedule
    public func approveDeletionRequest(requestId: UUID, by caregiver: UserIdentity) {
        guard let reqIndex = pendingDeletionRequests.firstIndex(where: { $0.id == requestId }) else { return }
        let request = pendingDeletionRequests[reqIndex]
        guard canRespond(to: request, caregiverId: caregiver.id) else {
            showToast("لا تملك صلاحية الرد على طلب الحذف هذا.")
            return
        }

        let now = AppClock.shared.now
        reconcilePastAndMidnightDoses(at: now)
        reconcileMissedDosesForToday(at: now)

        // 1. Cancel future reminders (UC-11 S#5)
        cancelReminder(id: request.medicationId)

        // 2. Remove medication permanently (UC-11 S#4)
        allMedications.removeAll(where: { $0.id == request.medicationId })

        // 3. Remove request
        pendingDeletionRequests.remove(at: reqIndex)

        // 4. Persist and refresh (UC-11 S#6)
        persistMedications()
        persistDeletionRequests()
        refreshDerivedState()
        CloudKitSyncManager.shared.publishMedicationDeletion(medicationId: request.medicationId, patientId: request.patientId)
        CloudKitSyncManager.shared.publishDeletionRequestRemoval(requestId: request.id, patientId: request.patientId)

        showToast("تمت الموافقة على حذف دواء \"\(request.medicationName)\" وحذفه نهائياً.")
    }

    /// UC-11: Caregiver rejects deletion request -> keeps medication active in patient's schedule
    public func rejectDeletionRequest(requestId: UUID, by caregiver: UserIdentity) {
        guard let reqIndex = pendingDeletionRequests.firstIndex(where: { $0.id == requestId }) else { return }
        let request = pendingDeletionRequests[reqIndex]
        guard canRespond(to: request, caregiverId: caregiver.id) else {
            showToast("لا تملك صلاحية الرد على طلب الحذف هذا.")
            return
        }

        // 1. Restore medication (clear pending flag, keep active in schedule)
        if let medIndex = allMedications.firstIndex(where: { $0.id == request.medicationId }) {
            allMedications[medIndex].isPendingDeletion = false
            persistMedications()
            refreshDerivedState()
            CloudKitSyncManager.shared.publishMedication(allMedications[medIndex])
        }

        // 2. Remove request
        pendingDeletionRequests.remove(at: reqIndex)
        persistDeletionRequests()
        CloudKitSyncManager.shared.publishDeletionRequestRemoval(requestId: request.id, patientId: request.patientId)

        showToast("تم رفض حذف دواء \"\(request.medicationName)\" والاحتفاظ به في جدول المستفيد.")
    }

    // MARK: - UC-6 Confirm Dose Taken
    /// UC-6: Confirms a dose occurrence (specific `slotMinutes` or primary/active slot), records timestamp, updates status and notifies caregivers.
    @discardableResult
    public func confirmDoseTaken(
        id: UUID,
        slotMinutes: Int? = nil,
        patient: UserIdentity,
        at overrideNow: Date? = nil
    ) -> Bool {
        let now = overrideNow ?? AppClock.shared.now
        reconcilePastAndMidnightDoses(at: now)
        reconcileMissedDosesForToday(at: now)

        guard let index = allMedications.firstIndex(where: { $0.id == id && $0.patientId == patient.id }) else { return false }

        let med = allMedications[index]
        let slots = dailyDoseTimesMinutes(for: med)
        let resolvedSlot: Int
        let isCarryover: Bool

        if let slotMinutes {
            resolvedSlot = slotMinutes
            isCarryover = hasActiveCarryoverFromYesterday(med, slotMinutes: slotMinutes, at: now)
        } else if let carryoverOverdue = slots.first(where: {
            hasActiveCarryoverFromYesterday(med, slotMinutes: $0, at: now) &&
            doseInteractionState(for: med, slotMinutes: $0, at: now, isCarryover: true) == .overdueLate
        }) {
            resolvedSlot = carryoverOverdue
            isCarryover = true
        } else if let todayOverdue = slots.first(where: {
            isScheduledForToday(med, on: now) &&
            doseInteractionState(for: med, slotMinutes: $0, at: now, isCarryover: false) == .overdueLate
        }) {
            resolvedSlot = todayOverdue
            isCarryover = false
        } else if let carryoverDue = slots.first(where: {
            hasActiveCarryoverFromYesterday(med, slotMinutes: $0, at: now) &&
            doseInteractionState(for: med, slotMinutes: $0, at: now, isCarryover: true) == .dueOnTime
        }) {
            resolvedSlot = carryoverDue
            isCarryover = true
        } else if let todayDue = slots.first(where: {
            isScheduledForToday(med, on: now) &&
            doseInteractionState(for: med, slotMinutes: $0, at: now, isCarryover: false) == .dueOnTime
        }) {
            resolvedSlot = todayDue
            isCarryover = false
        } else {
            resolvedSlot = slots.first ?? scheduledMinutes(for: med)
            isCarryover = hasActiveCarryoverFromYesterday(med, slotMinutes: resolvedSlot, at: now)
        }

        // Guard against double-tap / already confirmed slot or out-of-window dose
        let currentState = doseInteractionState(for: med, slotMinutes: resolvedSlot, at: now, isCarryover: isCarryover)
        guard currentState == .dueOnTime || currentState == .overdueLate else {
            if currentState == .missed {
                let missDay = isCarryover
                    ? (Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now)
                    : now
                adherenceService.recordDoseMissedIfNeeded(
                    medication: med,
                    patientId: patient.id,
                    on: missDay,
                    slotMinutes: resolvedSlot
                )
                showToast("انتهى وقت تأكيد جرعة «\(med.name)» وتم تسجيلها كجرعة فائتة.")
            }
            return false
        }

        let medName = med.name
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)

        if isCarryover, let yesterday {
            // Confirm yesterday's midnight-crossing occurrence without marking today's future slot as taken
            adherenceService.recordDoseTaken(
                medication: allMedications[index],
                patientId: patient.id,
                takenAt: now,
                scheduledDay: yesterday,
                slotMinutes: resolvedSlot
            )
        } else {
            allMedications[index].takenSlotsToday[resolvedSlot] = now
            allMedications[index].takenAt = now
            allMedications[index].isTaken = !slots.isEmpty && slots.allSatisfy {
                isSlotTakenToday(allMedications[index], slotMinutes: $0, on: now)
            }
            persistMedications()
            CloudKitSyncManager.shared.publishMedication(allMedications[index])

            // UC-7: Record in dose log for weekly adherence report
            adherenceService.recordDoseTaken(
                medication: allMedications[index],
                patientId: patient.id,
                takenAt: now,
                scheduledDay: now,
                slotMinutes: resolvedSlot
            )
        }

        // Refresh derived schedule and remainingDoses count
        refreshDerivedState(at: now)

        // UC-5: Re-plan missed-dose alerts (skips confirmed slot(s) today while keeping remaining slots & future days armed)
        if schedulesSystemNotifications, let updatedMed = allMedications.first(where: { $0.id == id }) {
            Task { await self.scheduleMissedDoseAlert(for: updatedMed) }
        }

        // UC-6 S#6: Notify connected caregivers
        relationshipService.notifyCaregiversDoseTaken(
            medicationName: medName,
            patientName: patient.displayName
        )

        if self.remainingDoses > 0 {
            showToast("تم تأكيد جرعة «\(medName)». باقي \(self.remainingDoses) جرعات اليوم")
        } else {
            showToast("أكملت جميع جرعات اليوم")
        }
        return true
    }

    // MARK: - As-Needed Dose Logging («عند الحاجة»)
    public func logAsNeededDose(
        for item: MedicationItem,
        patient: UserIdentity,
        at overrideNow: Date? = nil
    ) {
        let now = overrideNow ?? AppClock.shared.now
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let currentMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        adherenceService.recordDoseTaken(
            medication: item,
            patientId: patient.id,
            takenAt: now,
            scheduledDay: now,
            slotMinutes: currentMinutes
        )

        showToast("تم تسجيل أخذ جرعة «\(item.name)» بنجاح.")
        relationshipService.notifyCaregiversDoseTaken(
            medicationName: item.name,
            patientName: patient.displayName
        )
    }

    // MARK: - Notification Action Handling (Quick Actions & Notification Taps)
    public func handleNotificationAction(
        medicationId: UUID,
        slotMinutes: Int? = nil,
        actionIdentifier: String,
        appState: AppState?
    ) {
        refreshDerivedState()
        guard let med = allMedications.first(where: { $0.id == medicationId }) else { return }

        let now = AppClock.shared.now
        let resolvedSlot = slotMinutes ?? dailyDoseTimesMinutes(for: med).first ?? scheduledMinutes(for: med)
        let isCarryover = hasActiveCarryoverFromYesterday(med, slotMinutes: resolvedSlot, at: now)
        let state = doseInteractionState(for: med, slotMinutes: resolvedSlot, at: now, isCarryover: isCarryover)

        if actionIdentifier == Self.confirmDoseActionIdentifier {
            switch state {
            case .dueOnTime, .overdueLate:
                if let patient = appState?.currentIdentity ?? KeychainService.shared.loadUserIdentity() {
                    _ = confirmDoseTaken(id: medicationId, slotMinutes: resolvedSlot, patient: patient)
                }
            case .missed:
                refreshDerivedState()
                showToast("انتهى وقت تأكيد جرعة «\(med.name)» وتم تسجيلها كجرعة فائتة.")
            case .upcomingBeforeWindow:
                showToast("لم يحن موعد جرعة «\(med.name)» بعد (الموعد الساعة \(formattedTimeString(forSlotMinutes: resolvedSlot))).")
            case .taken:
                showToast("تم تأكيد جرعة «\(med.name)» مسبقاً.")
            }
        } else {
            if state == .missed {
                refreshDerivedState()
                showToast("انتهى وقت تأكيد جرعة «\(med.name)» وتم تسجيلها كجرعة فائتة.")
            }
            appState?.openDoseConfirmation(for: medicationId, slotMinutes: slotMinutes)
        }
    }

    // MARK: - Validation Helpers (UC-3)
    private func validateRequiredFields(name: String, dosage: String, timeString: String) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDosage = dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTime = timeString.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanName.isEmpty || cleanDosage.isEmpty || cleanTime.isEmpty {
            throw MedicationError.missingRequiredFields
        }

        if cleanDosage.count < 2 {
            throw MedicationError.invalidDosage
        }
    }

    private func validateImageData(_ data: Data) throws {
        if data.count > maxImageSizeBytes {
            throw MedicationError.imageTooLarge
        }

        // Basic image signature check (JPEG, PNG, HEIC)
        let header = [UInt8](data.prefix(4))
        let isPNG = header.starts(with: [0x89, 0x50, 0x4E, 0x47])
        let isJPEG = header.starts(with: [0xFF, 0xD8])
        let isHEIC = data.count > 12 && data.prefix(12).contains(0x66) // 'ftyp'
        
        // If UIImage can decode it, it's valid
        if !isPNG && !isJPEG && !isHEIC && UIImage(data: data) == nil {
            throw MedicationError.unsupportedImageFormat
        }
    }

    /// A caregiver may change a patient's schedule only through an active link to that exact patient.
    private func validateCaregiverPermission(caregiverId: String, targetPatientId: String?) throws {
        guard let targetPatientId else {
            throw MedicationError.unauthorizedCaregiver
        }
        let activeRels = relationshipService.activeRelationships
        let hasActiveConnection = activeRels.contains { rel in
            rel.caregiverId == caregiverId && rel.isActive && rel.patientId == targetPatientId
        }

        if !hasActiveConnection {
            throw MedicationError.unauthorizedCaregiver
        }
    }

    // MARK: - UC-3 S#6 & S#9: Notification Scheduling
    public struct PlannedNotification: Equatable {
        public let identifier: String
        public let hour: Int
        public let minute: Int
        public let weekday: Int?
        public let year: Int?
        public let month: Int?
        public let day: Int?
        public let repeats: Bool
        public let slotMinutes: Int

        public init(
            identifier: String,
            hour: Int,
            minute: Int,
            weekday: Int? = nil,
            year: Int? = nil,
            month: Int? = nil,
            day: Int? = nil,
            repeats: Bool,
            slotMinutes: Int
        ) {
            self.identifier = identifier
            self.hour = hour
            self.minute = minute
            self.weekday = weekday
            self.year = year
            self.month = month
            self.day = day
            self.repeats = repeats
            self.slotMinutes = slotMinutes
        }

        fileprivate var dateComponents: DateComponents {
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute
            if let weekday { comps.weekday = weekday }
            if let year { comps.year = year }
            if let month { comps.month = month }
            if let day { comps.day = day }
            return comps
        }
    }

    /// Computes all dose reminder notification triggers for `item` across its daily frequency slots and selected weekdays/intervals.
    public func plannedReminders(for item: MedicationItem, at date: Date? = nil) -> [PlannedNotification] {
        // As-needed medications never receive scheduled notifications
        if item.scheduleType == .asNeeded {
            return []
        }

        let now = date ?? AppClock.shared.now
        let calendar = Calendar.current
        let slots = dailyDoseTimesMinutes(for: item)
        let weekdays = scheduledWeekdays(for: item)
        let interval = dayInterval(for: item.frequency)
        let isMonthly = item.frequency.contains("شهري")
        let anchorDate = effectiveScheduleStart(for: item)
        let anchorWeekday = calendar.component(.weekday, from: anchorDate)
        let anchorDayOfMonth = calendar.component(.day, from: anchorDate)

        // Rolling window: if medication has an endDate, or is every other day, schedule concrete dates for next 7 days
        let requiresConcreteWindow = (item.endDate != nil) || (item.scheduleType == .everyOtherDay) || (interval != nil && interval! > 1) || isMonthly

        var plans: [PlannedNotification] = []
        for slotMin in slots {
            let hour = slotMin / 60
            let minute = slotMin % 60

            if requiresConcreteWindow {
                var queued = 0
                for dayOffset in 0...7 where queued < 7 {
                    guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: now),
                          isScheduledForToday(item, on: candidateDay) else {
                        continue
                    }
                    let triggerDate = scheduledDateTime(for: item, on: candidateDay, slotMinutes: slotMin)
                    guard triggerDate > now else { continue }
                    let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
                    plans.append(
                        PlannedNotification(
                            identifier: "medication_reminder_\(item.id.uuidString)_s\(slotMin)_d\(queued)",
                            hour: comps.hour ?? hour,
                            minute: comps.minute ?? minute,
                            year: comps.year,
                            month: comps.month,
                            day: comps.day,
                            repeats: false,
                            slotMinutes: slotMin
                        )
                    )
                    queued += 1
                }
            } else if let weekdays {
                for weekday in weekdays {
                    plans.append(
                        PlannedNotification(
                            identifier: "medication_reminder_\(item.id.uuidString)_s\(slotMin)_w\(weekday)",
                            hour: hour,
                            minute: minute,
                            weekday: weekday,
                            repeats: true,
                            slotMinutes: slotMin
                        )
                    )
                }
            } else if interval == 7 {
                plans.append(
                    PlannedNotification(
                        identifier: "medication_reminder_\(item.id.uuidString)_s\(slotMin)_w\(anchorWeekday)",
                        hour: hour,
                        minute: minute,
                        weekday: anchorWeekday,
                        repeats: true,
                        slotMinutes: slotMin
                    )
                )
            } else {
                plans.append(
                    PlannedNotification(
                        identifier: "medication_reminder_\(item.id.uuidString)_s\(slotMin)",
                        hour: hour,
                        minute: minute,
                        repeats: true,
                        slotMinutes: slotMin
                    )
                )
            }
        }
        return plans
    }

    /// Computes missed-dose alert notification triggers (+30m after each daily slot), preserving future alerts even when today's slot is confirmed.
    public func plannedMissedDoseAlerts(
        for item: MedicationItem,
        at date: Date? = nil,
        skippingToday: Bool? = nil
    ) -> [PlannedNotification] {
        // As-needed medications never trigger missed dose alerts
        if item.scheduleType == .asNeeded {
            return []
        }

        let now = date ?? AppClock.shared.now
        let calendar = Calendar.current
        let slots = dailyDoseTimesMinutes(for: item)
        let weekdays = scheduledWeekdays(for: item)
        let interval = dayInterval(for: item.frequency)
        let isMonthly = item.frequency.contains("شهري")
        let anchorDate = effectiveScheduleStart(for: item)
        let anchorWeekday = calendar.component(.weekday, from: anchorDate)
        let anchorDayOfMonth = calendar.component(.day, from: anchorDate)

        // Rolling window: if medication has an endDate, or is every other day, schedule concrete dates for next 7 days
        let requiresConcreteWindow = (item.endDate != nil) || (item.scheduleType == .everyOtherDay) || (interval != nil && interval! > 1) || isMonthly

        var plans: [PlannedNotification] = []
        for slotMin in slots {
            let totalAlertMinutes = slotMin + DoseWindowConfig.lateThresholdMinutes
            let crossesMidnight = totalAlertMinutes >= 1440
            let alertMinutes = totalAlertMinutes % 1440
            let alertHour = alertMinutes / 60
            let alertMinute = alertMinutes % 60

            let todaySched = scheduledDateTime(for: item, on: now, slotMinutes: slotMin)
            let todayAlertDate = todaySched.addingTimeInterval(TimeInterval(DoseWindowConfig.lateThresholdMinutes * 60))
            let slotTakenToday = skippingToday ?? isSlotTakenToday(item, slotMinutes: slotMin, on: now)
            let shouldSkipToday = slotTakenToday && isScheduledForToday(item, on: now) && now < todayAlertDate

            if requiresConcreteWindow {
                var queuedCount = 0
                for dayOffset in 0...7 where queuedCount < 7 {
                    guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: now),
                          isScheduledForToday(item, on: candidateDay) else {
                        continue
                    }
                    if dayOffset == 0 && shouldSkipToday {
                        continue
                    }
                    let nextAlertDate = scheduledDateTime(for: item, on: candidateDay, slotMinutes: slotMin)
                        .addingTimeInterval(TimeInterval(DoseWindowConfig.lateThresholdMinutes * 60))
                    guard nextAlertDate > now else { continue }
                    let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextAlertDate)
                    plans.append(
                        PlannedNotification(
                            identifier: "medication_missed_dose_\(item.id.uuidString)_s\(slotMin)_next_\(queuedCount)",
                            hour: comps.hour ?? alertHour,
                            minute: comps.minute ?? alertMinute,
                            year: comps.year,
                            month: comps.month,
                            day: comps.day,
                            repeats: false,
                            slotMinutes: slotMin
                        )
                    )
                    queuedCount += 1
                }
            } else if shouldSkipToday {
                if let weekdays, weekdays.count > 1 {
                    let todayWeekday = calendar.component(.weekday, from: now)
                    for weekday in weekdays where weekday != todayWeekday {
                        let alertWeekday = crossesMidnight ? ((weekday % 7) + 1) : weekday
                        plans.append(
                            PlannedNotification(
                                identifier: "medication_missed_dose_\(item.id.uuidString)_s\(slotMin)_w\(alertWeekday)",
                                hour: alertHour,
                                minute: alertMinute,
                                weekday: alertWeekday,
                                repeats: true,
                                slotMinutes: slotMin
                            )
                        )
                    }
                    if let nextSameWeekday = calendar.date(byAdding: .day, value: 7, to: now) {
                        let nextAlertDate = scheduledDateTime(for: item, on: nextSameWeekday, slotMinutes: slotMin)
                            .addingTimeInterval(TimeInterval(DoseWindowConfig.lateThresholdMinutes * 60))
                        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextAlertDate)
                        plans.append(
                            PlannedNotification(
                                identifier: "medication_missed_dose_\(item.id.uuidString)_s\(slotMin)_next_0",
                                hour: comps.hour ?? alertHour,
                                minute: comps.minute ?? alertMinute,
                                year: comps.year,
                                month: comps.month,
                                day: comps.day,
                                repeats: false,
                                slotMinutes: slotMin
                            )
                        )
                    }
                } else {
                    var queuedCount = 0
                    let searchHorizon = 7
                    for dayOffset in 1...searchHorizon where queuedCount < 3 {
                        guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: now),
                              isScheduledForToday(item, on: candidateDay) else {
                            continue
                        }
                        let nextAlertDate = scheduledDateTime(for: item, on: candidateDay, slotMinutes: slotMin)
                            .addingTimeInterval(TimeInterval(DoseWindowConfig.lateThresholdMinutes * 60))
                        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextAlertDate)
                        plans.append(
                            PlannedNotification(
                                identifier: "medication_missed_dose_\(item.id.uuidString)_s\(slotMin)_next_\(queuedCount)",
                                hour: comps.hour ?? alertHour,
                                minute: comps.minute ?? alertMinute,
                                year: comps.year,
                                month: comps.month,
                                day: comps.day,
                                repeats: false,
                                slotMinutes: slotMin
                            )
                        )
                        queuedCount += 1
                    }
                }
            } else if let weekdays {
                for weekday in weekdays {
                    let alertWeekday = crossesMidnight ? ((weekday % 7) + 1) : weekday
                    plans.append(
                        PlannedNotification(
                            identifier: "medication_missed_dose_\(item.id.uuidString)_s\(slotMin)_w\(alertWeekday)",
                            hour: alertHour,
                            minute: alertMinute,
                            weekday: alertWeekday,
                            repeats: true,
                            slotMinutes: slotMin
                        )
                    )
                }
            } else if interval == 7 {
                let alertWeekday = crossesMidnight ? ((anchorWeekday % 7) + 1) : anchorWeekday
                plans.append(
                    PlannedNotification(
                        identifier: "medication_missed_dose_\(item.id.uuidString)_s\(slotMin)_w\(alertWeekday)",
                        hour: alertHour,
                        minute: alertMinute,
                        weekday: alertWeekday,
                        repeats: true,
                        slotMinutes: slotMin
                    )
                )
            } else {
                plans.append(
                    PlannedNotification(
                        identifier: "medication_missed_dose_\(item.id.uuidString)_s\(slotMin)",
                        hour: alertHour,
                        minute: alertMinute,
                        repeats: true,
                        slotMinutes: slotMin
                    )
                )
            }
        }
        return plans
    }

    private func knownNotificationIdentifiers(for id: UUID) -> [String] {
        var ids = [
            "medication_reminder_\(id.uuidString)",
            "medication_missed_dose_\(id.uuidString)",
            "medication_missed_dose_next_\(id.uuidString)"
        ]
        for w in 1...7 {
            ids.append("medication_reminder_\(id.uuidString)_w\(w)")
            ids.append("medication_missed_dose_\(id.uuidString)_w\(w)")
        }
        if let item = allMedications.first(where: { $0.id == id }) {
            for slot in dailyDoseTimesMinutes(for: item) {
                ids.append("medication_reminder_\(id.uuidString)_s\(slot)")
                ids.append("medication_missed_dose_\(id.uuidString)_s\(slot)")
                for w in 1...7 {
                    ids.append("medication_reminder_\(id.uuidString)_s\(slot)_w\(w)")
                    ids.append("medication_missed_dose_\(id.uuidString)_s\(slot)_w\(w)")
                }
                for k in 0..<3 {
                    ids.append("medication_missed_dose_\(id.uuidString)_s\(slot)_next_\(k)")
                }
            }
        }
        return ids
    }

    private func removePendingRequests(matchingPrefixes prefixes: [String], center: UNUserNotificationCenter) async {
        let pending = await center.pendingNotificationRequests()
        let matching = pending.map(\.identifier).filter { identifier in
            prefixes.contains { prefix in identifier.hasPrefix(prefix) }
        }
        if !matching.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: matching)
        }
    }

    public func scheduleReminder(for item: MedicationItem) async -> Bool {
        guard schedulesSystemNotifications else { return true }
        let enabled = UserDefaults.standard.object(forKey: "dawai_notifications_enabled") as? Bool ?? true
        guard enabled else {
            return true
        }

        let center = UNUserNotificationCenter.current()

        // 1. On iOS 26+, schedule full-screen AlarmKit alarms (no snooze) on the patient's own device when enabled.
        let isLocalPatientDevice = KeychainService.shared.loadUserIdentity()?.id == item.patientId
        var usedAlarmKit = false
        if isLocalPatientDevice {
            usedAlarmKit = await MedicationAlarmService.shared.scheduleAlarms(for: item, using: self)
        } else {
            MedicationAlarmService.shared.cancelAlarms(forMedicationId: item.id)
        }

        do {
            let settings = await center.notificationSettings()
            var isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional

            if settings.authorizationStatus == .notDetermined {
                isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            }

            await removePendingRequests(
                matchingPrefixes: ["medication_reminder_\(item.id.uuidString)"],
                center: center
            )

            // 2. If AlarmKit is not active/authorized on this device, schedule standard local notification reminders.
            if !usedAlarmKit {
                guard isAuthorized else {
                    return false
                }

                let plans = plannedReminders(for: item)
                for plan in plans {
                    let slotTime = formattedTimeString(forSlotMinutes: plan.slotMinutes)
                    let content = UNMutableNotificationContent()
                    content.title = "تذكير بموعد دواء: \(item.name)"
                    content.body = "حان موعد تناول الجرعة (\(item.dosage)) - \(slotTime)"
                    if let instructions = item.instructions, !instructions.isEmpty {
                        content.body += "\nتعليمات: \(instructions)"
                    }
                    content.sound = .default
                    content.categoryIdentifier = Self.doseReminderCategoryIdentifier
                    content.userInfo = [
                        "medicationId": item.id.uuidString,
                        "slotMinutes": plan.slotMinutes,
                        "timeString": slotTime,
                        "type": "dose_reminder"
                    ]

                    let trigger = UNCalendarNotificationTrigger(dateMatching: plan.dateComponents, repeats: plan.repeats)
                    let request = UNNotificationRequest(
                        identifier: plan.identifier,
                        content: content,
                        trigger: trigger
                    )
                    try await center.add(request)
                }
            }

            // UC-5 S#2 & S#3: Schedule Missed-Dose Alert for Caregiver (30 minutes after each scheduled dose time)
            if isAuthorized {
                await scheduleMissedDoseAlert(for: item)
            }

            return usedAlarmKit || isAuthorized
        } catch {
            return usedAlarmKit
        }
    }

    /// UC-5 S#2 & S#3: Schedules missed-dose alerts 30 minutes after each scheduled slot of `item`.
    /// Does nothing when reminders are switched off in Settings or notifications are not authorized.
    public func scheduleMissedDoseAlert(for item: MedicationItem, skippingToday: Bool? = nil) async {
        guard schedulesSystemNotifications else { return }
        let enabled = UserDefaults.standard.object(forKey: "dawai_notifications_enabled") as? Bool ?? true
        guard enabled else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        await removePendingRequests(
            matchingPrefixes: ["medication_missed_dose_\(item.id.uuidString)"],
            center: center
        )

        let plans = plannedMissedDoseAlerts(for: item, skippingToday: skippingToday)
        for plan in plans {
            let slotTime = formattedTimeString(forSlotMinutes: plan.slotMinutes)
            let missedContent = UNMutableNotificationContent()
            missedContent.title = "تنبيه تأخر جرعة: \(item.name)"
            missedContent.body = "لم يتم تأكيد أخذ جرعة \(item.name) (\(item.dosage)) بعد مرور \(DoseWindowConfig.lateThresholdMinutes) دقيقة من موعدها (\(slotTime))."
            missedContent.sound = .default
            missedContent.userInfo = [
                "medicationId": item.id.uuidString,
                "slotMinutes": plan.slotMinutes,
                "medicationName": item.name,
                "dosage": item.dosage,
                "timeString": slotTime,
                "patientId": item.patientId,
                "type": "missed_dose_alert"
            ]

            let missedTrigger = UNCalendarNotificationTrigger(dateMatching: plan.dateComponents, repeats: plan.repeats)
            let missedRequest = UNNotificationRequest(
                identifier: plan.identifier,
                content: missedContent,
                trigger: missedTrigger
            )
            try? await center.add(missedRequest)
        }
    }

    public func cancelReminder(id: UUID) {
        guard schedulesSystemNotifications else { return }
        MedicationAlarmService.shared.cancelAlarms(forMedicationId: id)
        let center = UNUserNotificationCenter.current()
        let identifiers = knownNotificationIdentifiers(for: id)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        let prefixes = [
            "medication_reminder_\(id.uuidString)",
            "medication_missed_dose_\(id.uuidString)"
        ]
        Task {
            await removePendingRequests(matchingPrefixes: prefixes, center: center)
        }
    }

    /// UC-5: Cancels pending and delivered missed dose alerts for `id`
    public func cancelMissedDoseAlert(id: UUID) {
        guard schedulesSystemNotifications else { return }
        let center = UNUserNotificationCenter.current()
        let identifiers = knownNotificationIdentifiers(for: id).filter { $0.hasPrefix("medication_missed_dose_") }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        let prefixes = ["medication_missed_dose_\(id.uuidString)"]
        Task {
            await removePendingRequests(matchingPrefixes: prefixes, center: center)
        }
    }

    /// Proactively requests notification permissions if not yet determined (e.g. on first Home view appearance)
    @discardableResult
    public func requestNotificationPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                UserDefaults.standard.set(granted, forKey: "dawai_notifications_enabled")
                return granted
            } catch {
                return false
            }
        }
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Simulator testing helper: triggers an immediate reminder after `delaySeconds` with notification payload (UC-4)
    @discardableResult
    public func simulateInstantReminder(for item: MedicationItem, delaySeconds: TimeInterval = 3) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "تذكير بموعد دواء: \(item.name)"
        content.body = "حان موعد تناول الجرعة (\(item.dosage)) - \(item.timeString)"
        if let instructions = item.instructions, !instructions.isEmpty {
            content.body += "\nتعليمات: \(instructions)"
        }
        content.sound = .default
        content.categoryIdentifier = Self.doseReminderCategoryIdentifier
        content.userInfo = [
            "medicationId": item.id.uuidString,
            "type": "dose_reminder"
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delaySeconds, 1), repeats: false)
        let request = UNNotificationRequest(
            identifier: "sim_instant_\(item.id.uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            showToast("سيصلك إشعار التذكير لدواء \"\(item.name)\" بعد \(Int(delaySeconds)) ثوانٍ.")
            return true
        } catch {
            return false
        }
    }

    /// Simulator testing helper: triggers an immediate missed-dose alert for Caregiver after `delaySeconds` (UC-5)
    @discardableResult
    public func simulateInstantMissedDoseAlert(for item: MedicationItem, delaySeconds: TimeInterval = 3) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "تنبيه تأخر جرعة: \(item.name)"
        content.body = "لم يتم تأكيد أخذ جرعة \(item.name) (\(item.dosage)) بعد مرور \(DoseWindowConfig.lateThresholdMinutes) دقيقة من موعدها."
        content.sound = .default
        content.userInfo = [
            "medicationId": item.id.uuidString,
            "medicationName": item.name,
            "dosage": item.dosage,
            "timeString": item.timeString,
            "patientId": item.patientId,
            "type": "missed_dose_alert"
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delaySeconds, 1), repeats: false)
        let request = UNNotificationRequest(
            identifier: "sim_instant_missed_\(item.id.uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            showToast("سيصلك تنبيه تأخر جرعة \"\(item.name)\" بعد \(Int(delaySeconds)) ثوانٍ.")
            return true
        } catch {
            return false
        }
    }

    // MARK: - Notification Management (Backend Engine)
    public enum NotificationToggleResult {
        case enabled(scheduledCount: Int)
        case disabled
        case permissionDenied
        case failed(Error)
    }

    /// Checks the real iOS system authorization status
    public func checkSystemNotificationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    /// Toggles reminders on or off based on Settings preference with full system integration
    @discardableResult
    public func setNotificationsEnabled(_ enabled: Bool) async -> NotificationToggleResult {
        let center = UNUserNotificationCenter.current()

        if !enabled {
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
            MedicationAlarmService.shared.cancelAllAlarms()
            DoseLiveActivityManager.shared.endAllActivities()
            UserDefaults.standard.set(false, forKey: "dawai_notifications_enabled")
            showToast("تم إيقاف تنبيهات مواعيد الأدوية")
            return .disabled
        } else {
            let settings = await center.notificationSettings()
            var isAuthorized = false

            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                isAuthorized = true
            } else if settings.authorizationStatus == .notDetermined {
                do {
                    isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                } catch {
                    return .failed(error)
                }
            } else if settings.authorizationStatus == .denied {
                UserDefaults.standard.set(false, forKey: "dawai_notifications_enabled")
                return .permissionDenied
            }

            guard isAuthorized else {
                UserDefaults.standard.set(false, forKey: "dawai_notifications_enabled")
                return .permissionDenied
            }

            UserDefaults.standard.set(true, forKey: "dawai_notifications_enabled")

            // Reschedule reminders for all medications
            var scheduledCount = 0
            for med in allMedications {
                let success = await scheduleReminder(for: med)
                if success { scheduledCount += 1 }
            }

            if scheduledCount > 0 {
                showToast("تم تفعيل تنبيهات مواعيد الأدوية (\(scheduledCount) مواعيد)")
            } else {
                showToast("تم تفعيل تنبيهات مواعيد الأدوية بنجاح")
            }
            return .enabled(scheduledCount: scheduledCount)
        }
    }

    /// Toggles reminders on or off based on Settings preference
    public func updateNotificationPreference(enabled: Bool) async {
        _ = await setNotificationsEnabled(enabled)
    }

    /// Toggles iOS 26+ AlarmKit full-screen alarms on or off and reschedules all patient medications accordingly.
    @discardableResult
    public func setAlarmKitEnabled(_ enabled: Bool) async -> Bool {
        MedicationAlarmService.shared.isUserEnabled = enabled
        if !enabled {
            MedicationAlarmService.shared.cancelAllAlarms()
            for med in medications {
                _ = await scheduleReminder(for: med)
            }
            showToast("تم إيقاف المنبّه القوي والعودة للإشعارات العادية")
            return false
        }

        let authorized = await MedicationAlarmService.shared.requestAuthorizationIfNeeded()
        guard authorized else {
            MedicationAlarmService.shared.isUserEnabled = false
            return false
        }

        for med in medications {
            _ = await scheduleReminder(for: med)
        }
        showToast("تم تفعيل منبّه الدواء القوي بملء الشاشة")
        return true
    }

    // MARK: - Toast helper
    public func showToast(_ message: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            self.toastMessage = message
        }
    }

    public func dismissToast() {
        withAnimation(.easeInOut(duration: 0.25)) {
            self.toastMessage = nil
        }
    }
}

// MARK: - UC-4 S#4: Notification Center Delegate
@MainActor
public final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = NotificationDelegate()

    public weak var appState: AppState?
    private var pendingBeneficiary: BeneficiarySummary?
    private var pendingDoseAction: (medicationId: UUID, slotMinutes: Int?, actionIdentifier: String)?

    private override init() {
        super.init()
    }

    public func configure(with appState: AppState) {
        self.appState = appState
        UNUserNotificationCenter.current().delegate = self

        if let pending = pendingBeneficiary {
            self.pendingBeneficiary = nil
            appState.openCaregiverPatientDetail(for: pending)
        }
        if let pendingAction = pendingDoseAction {
            self.pendingDoseAction = nil
            MedicationService.shared.handleNotificationAction(
                medicationId: pendingAction.medicationId,
                slotMinutes: pendingAction.slotMinutes,
                actionIdentifier: pendingAction.actionIdentifier,
                appState: appState
            )
        }
    }

    @MainActor
    public func openDoseFromAlarm(medicationId: UUID, slotMinutes: Int?) {
        if let appState {
            appState.openDoseConfirmation(for: medicationId, slotMinutes: slotMinutes)
        } else {
            pendingDoseAction = (
                medicationId: medicationId,
                slotMinutes: slotMinutes,
                actionIdentifier: UNNotificationDefaultActionIdentifier
            )
        }
    }

    private func resolveBeneficiaryForMissedDoseAlert(
        medicationId: UUID?,
        medicationName: String,
        dosage: String,
        timeString: String?,
        payloadPatientId: String?
    ) -> BeneficiarySummary {
        let med = medicationId.flatMap { id in
            MedicationService.shared.allMedications.first(where: { $0.id == id })
        }
        let rawPatientId = payloadPatientId ?? med?.patientId

        let relationship: ActiveRelationship?
        if let currentId = appState?.currentIdentity?.id,
           let pid = rawPatientId,
           let matched = RelationshipService.shared.activeRelationships.first(where: {
               $0.caregiverId == currentId && $0.patientId == pid && $0.isActive
           }) {
            relationship = matched
        } else if let pid = rawPatientId,
                  let matched = RelationshipService.shared.activeRelationships.first(where: {
                      $0.patientId == pid && $0.isActive
                  }) {
            relationship = matched
        } else if appState?.currentIdentity?.role == .caregiver,
                  let currentId = appState?.currentIdentity?.id,
                  let matched = RelationshipService.shared.activeRelationships.first(where: {
                      $0.caregiverId == currentId && $0.isActive
                  }) {
            relationship = matched
        } else {
            relationship = nil
        }

        let resolvedPatientId = relationship?.patientId ?? rawPatientId
        let demoMatch = DemoModeService.shared.beneficiaries.first(where: { $0.patientId == resolvedPatientId })
            ?? (resolvedPatientId == nil ? DemoModeService.shared.beneficiaries.first : nil)
        let storedPatient = KeychainService.shared.loadUserIdentity(forRole: .patient)

        let resolvedName: String =
            relationship?.patientDisplayName
            ?? demoMatch?.name
            ?? (storedPatient?.id == resolvedPatientId ? storedPatient?.displayName : nil)
            ?? (appState?.currentIdentity?.role == .patient && appState?.currentIdentity?.id == resolvedPatientId ? appState?.currentIdentity?.displayName : nil)
            ?? "المستفيد"

        let resolvedMedName = medicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (med?.name ?? "الدواء")
            : medicationName
        let resolvedDosage = dosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? med?.dosage
            : dosage
        let resolvedTimeString = (timeString?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? timeString : nil)
            ?? med?.timeString

        return BeneficiarySummary(
            id: relationship?.id ?? demoMatch?.id ?? UUID(),
            patientId: resolvedPatientId ?? demoMatch?.patientId,
            name: resolvedName,
            hasDelayAlert: true,
            delayNotice: "\(DoseWindowConfig.lateThresholdMinutes) د تأخير، \(resolvedMedName)",
            scheduledTime: resolvedTimeString,
            isInvitation: false,
            delayedMedicationName: resolvedMedName,
            delayedDosage: resolvedDosage,
            phoneNumber: demoMatch?.phoneNumber ?? "0501234567"
        )
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let notifType = userInfo["type"] as? String ?? "dose_reminder"

        if notifType == "missed_dose_alert" {
            // UC-5 S#5: Caregiver opens missed-dose notification -> system routes directly to patient detail
            let medName = userInfo["medicationName"] as? String ?? "الدواء"
            let dosage = userInfo["dosage"] as? String ?? ""
            let payloadTimeString = userInfo["timeString"] as? String
            let payloadPatientId = userInfo["patientId"] as? String
            let medicationId = (userInfo["medicationId"] as? String).flatMap(UUID.init(uuidString:))
            Task { @MainActor in
                let beneficiary = self.resolveBeneficiaryForMissedDoseAlert(
                    medicationId: medicationId,
                    medicationName: medName,
                    dosage: dosage,
                    timeString: payloadTimeString,
                    payloadPatientId: payloadPatientId
                )
                if let appState = self.appState {
                    appState.openCaregiverPatientDetail(for: beneficiary)
                } else {
                    self.pendingBeneficiary = beneficiary
                }
                completionHandler()
            }
            return
        } else if let medIdString = userInfo["medicationId"] as? String,
                  let medId = UUID(uuidString: medIdString) {
            let actionId = response.actionIdentifier
            let slotMinutes = userInfo["slotMinutes"] as? Int
            Task { @MainActor in
                if self.appState == nil && actionId == UNNotificationDefaultActionIdentifier {
                    self.pendingDoseAction = (medId, slotMinutes, actionId)
                } else {
                    MedicationService.shared.handleNotificationAction(
                        medicationId: medId,
                        slotMinutes: slotMinutes,
                        actionIdentifier: actionId,
                        appState: self.appState
                    )
                }
                completionHandler()
            }
            return
        }
        completionHandler()
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }
}
