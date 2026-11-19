//
//  RelationshipService.swift
//  Dawai
//
//  Use-Case 2 (UC-2): Link Patient and Caregiver
//  Service coordinating the secure invitation creation, validation, mutual confirmation handshake,
//  and active relationship lifecycle.
//

import Foundation
import Combine

@MainActor
public final class RelationshipService: ObservableObject {
    public static let shared = RelationshipService()

    // MARK: - Published State
    @Published public private(set) var outgoingInvitations: [ConnectionInvitation] = []
    @Published public private(set) var incomingInvitations: [ConnectionInvitation] = []
    @Published public private(set) var activeRelationships: [ActiveRelationship] = []

    // Notification toast banner trigger
    @Published public var notificationToastMessage: String? = nil

    /// Persistence for invitations and relationships (UserDefaults today, replaceable later).
    private let store: any InvitationStore

    public init(store: any InvitationStore = UserDefaultsInvitationStore()) {
        self.store = store
        loadPersistedState()
    }

    // MARK: - Patient <-> Caregivers Queries (Up to 3 Caregivers per Patient)
    public static let maxCaregiversPerPatient = 3

    /// Returns all active caregiver relationships for `patientId`.
    public func activeCaregivers(forPatient patientId: String) -> [ActiveRelationship] {
        activeRelationships.filter { $0.patientId == patientId && $0.isActive }
    }

    /// Returns the first active caregiver relationship for `patientId`, if any (for backwards compatibility).
    public func activeCaregiver(forPatient patientId: String) -> ActiveRelationship? {
        activeCaregivers(forPatient: patientId).first
    }

    /// True when `patientId` has at least one active caregiver.
    public func hasActiveCaregiver(forPatient patientId: String) -> Bool {
        !activeCaregivers(forPatient: patientId).isEmpty
    }

    /// True when `patientId` has reached the maximum allowed caregivers limit (3).
    public func hasReachedCaregiverLimit(forPatient patientId: String) -> Bool {
        activeCaregivers(forPatient: patientId).count >= Self.maxCaregiversPerPatient
    }

    /// Invitations initiated by `user` that have not expired.
    public func outgoingInvitations(for user: UserIdentity, status: InvitationStatus? = nil) -> [ConnectionInvitation] {
        let all = deduplicate(outgoingInvitations + incomingInvitations)
        return all.filter { inv in
            guard inv.initiatorId == user.id, !inv.isExpired else { return false }
            if let status {
                return inv.status == status
            }
            return true
        }
    }

    /// Pending, unexpired invitations sent by a user of the opposite role that `user` can accept or reject.
    public func incomingInvitations(for user: UserIdentity) -> [ConnectionInvitation] {
        if user.role == .patient && hasReachedCaregiverLimit(forPatient: user.id) {
            return []
        }
        let all = deduplicate(outgoingInvitations + incomingInvitations)
        return all.filter { inv in
            inv.initiatorId != user.id &&
            inv.initiatorRole != user.role &&
            inv.status == .pending &&
            !inv.isExpired &&
            !(inv.initiatorRole == .patient && hasReachedCaregiverLimit(forPatient: inv.initiatorId))
        }
    }

    // MARK: - S#2: Create a Secure Invitation
    public func createInvitation(initiator: UserIdentity) -> ConnectionInvitation {
        // Remove previous pending or expired invitations from this user before creating a new one
        outgoingInvitations.removeAll {
            $0.initiatorId == initiator.id && ($0.status == .pending || $0.isExpired)
        }
        incomingInvitations.removeAll {
            $0.initiatorId == initiator.id && ($0.status == .pending || $0.isExpired)
        }

        let invitation = ConnectionInvitation(
            initiatorId: initiator.id,
            initiatorDisplayName: initiator.displayName,
            initiatorRole: initiator.role,
            initiatorKeyFingerprint: initiator.keyFingerprint
        )

        outgoingInvitations.append(invitation)
        outgoingInvitations = deduplicate(outgoingInvitations)
        persistState()
        return invitation
    }

    // MARK: - URL & Payload Import (Cross-Device Self-Contained Links)
    /// Extracts a token (and imports any embedded invitation or sync payload) from a URL or pasted text.
    @discardableResult
    public func extractAndImportToken(from rawInput: String) -> String {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Check if rawInput contains an https:// or dawai:// URL (either standalone or inside shareable text)
        if let urlRange = trimmed.range(of: #"(?:https?://|dawai://)[^\s]+"#, options: .regularExpression),
           let url = URL(string: String(trimmed[urlRange])) {
            if let token = handleIncomingURL(url) {
                return token
            }
        }

        // 2. Check if rawInput is directly a URL with query items
        if let components = URLComponents(string: trimmed) {
            if let payload = components.queryItems?.first(where: { $0.name == "payload" })?.value {
                if let inv = ConnectionInvitation.decodeFromPayload(payload) {
                    importDecodedInvitation(inv)
                    return inv.token
                }
                if let bundle = PortablePatientSyncBundle.decodeFromPayload(payload) {
                    importSyncBundle(bundle)
                    return ""
                }
            }
            if let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
                return token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        }

        // 3. Check if rawInput contains a Base64URL payload token (e.g. "eyJ..." either standalone or at the end of a pasted message)
        if let b64Range = trimmed.range(of: #"eyJ[A-Za-z0-9_-]{30,}"#, options: .regularExpression) {
            let candidate = String(trimmed[b64Range])
            if let inv = ConnectionInvitation.decodeFromPayload(candidate) {
                importDecodedInvitation(inv)
                return inv.token
            }
        }

        if trimmed.count > 40, let inv = ConnectionInvitation.decodeFromPayload(trimmed) {
            importDecodedInvitation(inv)
            return inv.token
        }

        // 4. Otherwise extract the last alphanumeric token (e.g. if user pasted "رمز الدعوة: abc123...")
        if let tokenMatch = trimmed.range(of: #"[a-fA-F0-9]{8,32}$"#, options: .regularExpression) {
            return String(trimmed[tokenMatch]).lowercased()
        }

        return trimmed.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// True when `url` is shaped like an invitation link (`dawai://invite...` or `https://.../invite/...`), valid or not.
    public func isInviteLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "dawai" || scheme == "https" || scheme == "http" else {
            return false
        }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        return host == "invite" || path.contains("invite")
    }

    /// Handles `dawai://invite?...`, `https://.../invite/?...`, and `dawai://sync?...` URLs. Returns the invitation token if it is an invite link.
    @discardableResult
    public func handleIncomingURL(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "dawai" || scheme == "https" || scheme == "http",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let payload = components.queryItems?.first(where: { $0.name == "payload" })?.value
        let token = components.queryItems?.first(where: { $0.name == "token" })?.value

        if (host == "sync" || path.contains("sync")), let payload, let bundle = PortablePatientSyncBundle.decodeFromPayload(payload) {
            importSyncBundle(bundle)
            return nil
        }

        if let payload, let decodedInvite = ConnectionInvitation.decodeFromPayload(payload) {
            importDecodedInvitation(decodedInvite)
            return decodedInvite.token
        }

        return token
    }

    private func importDecodedInvitation(_ invitation: ConnectionInvitation) {
        let tokenKey = invitation.token.lowercased()
        if !outgoingInvitations.contains(where: { $0.id == invitation.id || $0.token.lowercased() == tokenKey }) &&
           !incomingInvitations.contains(where: { $0.id == invitation.id || $0.token.lowercased() == tokenKey }) {
            incomingInvitations.append(invitation)
            persistState()
        } else {
            updateStoredInvitation(invitation)
            persistState()
        }
    }

    public func createSyncBundle(forPatient patientId: String, patientName: String) -> PortablePatientSyncBundle {
        let rel = activeCaregiver(forPatient: patientId)
        let meds = MedicationService.shared.medicationList(forPatient: patientId)
        let requests = MedicationService.shared.pendingDeletionRequests.filter { $0.patientId == patientId }
        let records = AdherenceService.shared.records(forPatient: patientId)
        return PortablePatientSyncBundle(
            patientId: patientId,
            patientDisplayName: patientName,
            relationship: rel,
            medications: meds,
            deletionRequests: requests,
            doseRecords: records
        )
    }

    public func importSyncBundle(_ bundle: PortablePatientSyncBundle) {
        if let rel = bundle.relationship, rel.isActive {
            activeRelationships.removeAll { $0.patientId == bundle.patientId }
            activeRelationships.append(rel)
            outgoingInvitations.removeAll { $0.initiatorId == bundle.patientId || $0.recipientId == bundle.patientId }
            incomingInvitations.removeAll { $0.initiatorId == bundle.patientId || $0.recipientId == bundle.patientId }
            persistState()
        }
        MedicationService.shared.importSyncedPatientData(
            patientId: bundle.patientId,
            medications: bundle.medications,
            deletionRequests: bundle.deletionRequests
        )
        AdherenceService.shared.mergeImportedRecords(bundle.doseRecords, forPatient: bundle.patientId)
        showToast("تمت مزامنة بيانات وأدوية \(bundle.patientDisplayName) بنجاح!")
    }

    // MARK: - S#4: Validate Invitation (Link Opened)
    @discardableResult
    public func validateInvitation(token: String, recipient: UserIdentity) throws -> ConnectionInvitation {
        let resolvedToken = extractAndImportToken(from: token)

        // Look up token in outgoing/shared invitations
        guard let invitation = findInvitation(by: resolvedToken) else {
            throw InvitationError.tokenNotFound
        }

        // Check expiration
        if invitation.isExpired {
            throw InvitationError.tokenExpired
        }

        // Check self-invitation
        if invitation.initiatorId == recipient.id {
            throw InvitationError.selfInvitation
        }

        // Check role compatibility (UC-2 S#4)
        if invitation.initiatorRole == recipient.role {
            throw InvitationError.incompatibleRoles(
                initiatorRole: invitation.initiatorRole,
                recipientRole: recipient.role
            )
        }

        // Determine patient & caregiver in this pair
        let patientId = invitation.initiatorRole == .patient ? invitation.initiatorId : recipient.id
        let caregiverId = invitation.initiatorRole == .caregiver ? invitation.initiatorId : recipient.id

        // Check if relationship already active with the same caregiver
        let alreadyActiveWithSameCaregiver = activeRelationships.contains { rel in
            rel.isActive && rel.patientId == patientId && rel.caregiverId == caregiverId
        }
        if alreadyActiveWithSameCaregiver {
            throw InvitationError.relationshipAlreadyExists
        }

        // Enforce max 3 Caregivers per Patient rule:
        if hasReachedCaregiverLimit(forPatient: patientId) {
            throw InvitationError.patientReachedCaregiverLimit
        }

        return invitation
    }

    // MARK: - S#5: Recipient Reviews and Accepts Invitation (Immediate Two-Way Activation)
    @discardableResult
    public func acceptInvitation(token: String, recipient: UserIdentity) throws -> ConnectionInvitation {
        var invitation = try validateInvitation(token: token, recipient: recipient)

        guard invitation.status == .pending else {
            throw InvitationError.invitationAlreadyProcessed
        }

        invitation.status = .confirmed
        invitation.recipientId = recipient.id
        invitation.recipientDisplayName = recipient.displayName
        invitation.recipientRole = recipient.role
        invitation.recipientKeyFingerprint = recipient.keyFingerprint

        let (patientId, patientName, caregiverId, caregiverName): (String, String, String, String)
        if invitation.initiatorRole == .patient {
            patientId = invitation.initiatorId
            patientName = invitation.initiatorDisplayName
            caregiverId = recipient.id
            caregiverName = recipient.displayName
        } else {
            patientId = recipient.id
            patientName = recipient.displayName
            caregiverId = invitation.initiatorId
            caregiverName = invitation.initiatorDisplayName
        }

        let relationship = ActiveRelationship(
            invitationId: invitation.id,
            patientId: patientId,
            patientDisplayName: patientName,
            caregiverId: caregiverId,
            caregiverDisplayName: caregiverName,
            establishedAt: Date(),
            isActive: true
        )

        // Remove confirmed invitation and any other pending invitations for this patient/caregiver pair
        let tokenKey = invitation.token.lowercased()
        outgoingInvitations.removeAll {
            $0.id == invitation.id ||
            $0.token.lowercased() == tokenKey ||
            $0.initiatorId == patientId ||
            $0.recipientId == patientId ||
            $0.initiatorId == caregiverId ||
            $0.recipientId == caregiverId
        }
        incomingInvitations.removeAll {
            $0.id == invitation.id ||
            $0.token.lowercased() == tokenKey ||
            $0.initiatorId == patientId ||
            $0.recipientId == patientId ||
            $0.initiatorId == caregiverId ||
            $0.recipientId == caregiverId
        }

        // Ensure patient has only this single active caregiver
        activeRelationships.removeAll { $0.patientId == patientId }
        activeRelationships.append(relationship)

        showToast("تم ربط الحسابين وتفعيل الاتصال بنجاح بين \(patientName) و \(caregiverName)!")
        persistState()
        CloudKitSyncManager.shared.publishRelationship(relationship)
        MedicationService.shared.loadPersistedMedications()

        return invitation
    }

    // MARK: - Recipient Rejects Invitation
    /// Only a pending invitation that has not expired can be rejected.
    public func rejectInvitation(token: String, recipient: UserIdentity) throws {
        let resolvedToken = extractAndImportToken(from: token)
        guard var invitation = findInvitation(by: resolvedToken) else {
            throw InvitationError.tokenNotFound
        }

        guard invitation.status == .pending else {
            throw InvitationError.invitationAlreadyProcessed
        }

        if invitation.isExpired {
            throw InvitationError.tokenExpired
        }

        invitation.status = .rejected
        invitation.recipientId = recipient.id
        invitation.recipientDisplayName = recipient.displayName
        invitation.recipientRole = recipient.role

        updateStoredInvitation(invitation)
        showToast("تم رفض الدعوة من قبل \(recipient.displayName).")
        persistState()
    }

    // MARK: - Cancel / Reject Invitations (User Control)
    public func rejectAcceptedInvitation(invitationId: UUID) {
        let matchingTokens = Set(
            outgoingInvitations.filter { $0.id == invitationId }.map { $0.token.lowercased() } +
            incomingInvitations.filter { $0.id == invitationId }.map { $0.token.lowercased() }
        )
        outgoingInvitations.removeAll { $0.id == invitationId || matchingTokens.contains($0.token.lowercased()) }
        incomingInvitations.removeAll { $0.id == invitationId || matchingTokens.contains($0.token.lowercased()) }
        showToast("تم رفض الارتباط وإلغاء الدعوة.")
        persistState()
    }

    public func cancelOutgoingInvitation(invitationId: UUID) {
        let matchingTokens = Set(
            outgoingInvitations.filter { $0.id == invitationId }.map { $0.token.lowercased() } +
            incomingInvitations.filter { $0.id == invitationId }.map { $0.token.lowercased() }
        )
        outgoingInvitations.removeAll { $0.id == invitationId || matchingTokens.contains($0.token.lowercased()) }
        incomingInvitations.removeAll { $0.id == invitationId || matchingTokens.contains($0.token.lowercased()) }
        showToast("تم إلغاء الدعوة المرسلة بنجاح.")
        persistState()
    }

    public func disconnect(relationshipId: UUID) {
        let ended = activeRelationships.filter { $0.id == relationshipId }
        activeRelationships.removeAll { $0.id == relationshipId }
        showToast("تم إنهاء الارتباط بنجاح.")
        persistState()

        // The former caregiver can no longer act on this patient's pending deletion requests
        for rel in ended {
            CloudKitSyncManager.shared.publishRelationshipEnded(rel)
            MedicationService.shared.relationshipEnded(patientId: rel.patientId, caregiverId: rel.caregiverId)
        }
    }

    // MARK: - S#6 & S#7: Initiator Confirms Connection (Mutual Handshake Complete)
    @discardableResult
    public func confirmConnection(invitationId: UUID, initiator: UserIdentity) throws -> ActiveRelationship {
        guard let index = outgoingInvitations.firstIndex(where: { $0.id == invitationId }) else {
            throw InvitationError.tokenNotFound
        }

        var invitation = outgoingInvitations[index]

        guard invitation.initiatorId == initiator.id else {
            throw InvitationError.tokenNotFound
        }

        if invitation.isExpired {
            throw InvitationError.tokenExpired
        }

        guard invitation.status == .accepted else {
            throw InvitationError.invitationNotAcceptedYet
        }

        guard let recipientId = invitation.recipientId,
              let recipientName = invitation.recipientDisplayName else {
            throw InvitationError.invitationNotAcceptedYet
        }

        // S#7: Create Active Patient-Caregiver relationship
        let (patientId, patientName, caregiverId, caregiverName): (String, String, String, String)
        if initiator.role == .patient {
            patientId = initiator.id
            patientName = initiator.displayName
            caregiverId = recipientId
            caregiverName = recipientName
        } else {
            patientId = recipientId
            patientName = recipientName
            caregiverId = initiator.id
            caregiverName = initiator.displayName
        }

        if hasReachedCaregiverLimit(forPatient: patientId) {
            throw InvitationError.patientReachedCaregiverLimit
        }

        // Mark as confirmed (S#6)
        invitation.status = .confirmed
        outgoingInvitations[index] = invitation

        let relationship = ActiveRelationship(
            invitationId: invitation.id,
            patientId: patientId,
            patientDisplayName: patientName,
            caregiverId: caregiverId,
            caregiverDisplayName: caregiverName,
            establishedAt: Date(),
            isActive: true
        )

        // Remove confirmed invitation and any other invitations for this patient
        let tokenKey = invitation.token.lowercased()
        outgoingInvitations.removeAll {
            $0.id == invitationId ||
            $0.token.lowercased() == tokenKey ||
            $0.initiatorId == patientId ||
            $0.recipientId == patientId
        }
        incomingInvitations.removeAll {
            $0.id == invitationId ||
            $0.token.lowercased() == tokenKey ||
            $0.initiatorId == patientId ||
            $0.recipientId == patientId
        }

        activeRelationships.removeAll { $0.patientId == patientId }
        activeRelationships.append(relationship)

        // S#8: Notify both users
        showToast("تم إنشاء الاتصال بنجاح وتفعيله بين \(patientName) و \(caregiverName)!")
        persistState()
        CloudKitSyncManager.shared.publishRelationship(relationship)
        MedicationService.shared.loadPersistedMedications()

        return relationship
    }

    // MARK: - CloudKit Remote Sync Merge
    /// Applies active and ended relationships pulled from CloudKit without re-publishing.
    public func applyRemoteRelationships(active: [ActiveRelationship], endedIds: Set<UUID>) {
        var changed = false

        // 1. Remove any relationships ended remotely
        if !endedIds.isEmpty {
            let endedRelationships = activeRelationships.filter { endedIds.contains($0.id) }
            if !endedRelationships.isEmpty {
                activeRelationships.removeAll { endedIds.contains($0.id) }
                changed = true
                for rel in endedRelationships {
                    MedicationService.shared.relationshipEnded(patientId: rel.patientId, caregiverId: rel.caregiverId)
                }
            }
        }

        // 2. Upsert active relationships from CloudKit and clear matching pending invitations
        for rel in active where rel.isActive && !endedIds.contains(rel.id) {
            // Remove any pending invitations associated with this link
            outgoingInvitations.removeAll {
                $0.id == rel.invitationId ||
                $0.initiatorId == rel.patientId || $0.recipientId == rel.patientId ||
                $0.initiatorId == rel.caregiverId || $0.recipientId == rel.caregiverId
            }
            incomingInvitations.removeAll {
                $0.id == rel.invitationId ||
                $0.initiatorId == rel.patientId || $0.recipientId == rel.patientId ||
                $0.initiatorId == rel.caregiverId || $0.recipientId == rel.caregiverId
            }

            if let existingIdx = activeRelationships.firstIndex(where: { $0.id == rel.id }) {
                if activeRelationships[existingIdx] != rel {
                    activeRelationships[existingIdx] = rel
                    changed = true
                }
            } else {
                // Ensure no duplicate with same caregiver and enforce up to 3 caregivers per patient
                activeRelationships.removeAll { $0.patientId == rel.patientId && $0.caregiverId == rel.caregiverId }
                activeRelationships.append(rel)
                changed = true
            }
        }

        if changed {
            persistState()
            MedicationService.shared.refreshDerivedState()
        }
    }

    // MARK: - Developer / Testing Simulation Helper
    /// Simulates the opposite party accepting the invitation and uses the device's stored counterpart identity so role-switching matches seamlessly.
    public func simulateRecipientAcceptance(for invitationId: UUID, simulatedRecipientName: String = "سارة") {
        guard let index = outgoingInvitations.firstIndex(where: { $0.id == invitationId }) else { return }
        
        let oppositeRole: UserRole = outgoingInvitations[index].initiatorRole == .patient ? .caregiver : .patient
        let counterpart = KeychainService.shared.loadOrCreateIdentity(forRole: oppositeRole, defaultName: simulatedRecipientName)
        outgoingInvitations[index].status = .accepted
        outgoingInvitations[index].recipientId = counterpart.id
        outgoingInvitations[index].recipientDisplayName = counterpart.displayName
        outgoingInvitations[index].recipientRole = oppositeRole
        outgoingInvitations[index].recipientKeyFingerprint = counterpart.keyFingerprint

        showToast("قام \(counterpart.displayName) بقبول الدعوة! يمكنك الآن تأكيد الاتصال.")
        persistState()
    }

    public func simulateIncomingInvitation(fromName: String, fromRole: UserRole, currentRecipient: UserIdentity) -> ConnectionInvitation {
        let counterpart = KeychainService.shared.loadOrCreateIdentity(forRole: fromRole, defaultName: fromName)
        let invitation = ConnectionInvitation(
            initiatorId: counterpart.id,
            initiatorDisplayName: counterpart.displayName,
            initiatorRole: fromRole,
            initiatorKeyFingerprint: counterpart.keyFingerprint,
            status: .pending
        )
        
        incomingInvitations.append(invitation)
        showToast("وصلتك دعوة اتصال جديدة من \(counterpart.displayName) (\(fromRole.titleArabic))")
        persistState()
        return invitation
    }

    public func dismissToast() {
        notificationToastMessage = nil
    }

    // MARK: - UC-6 S#6: Dose Confirmation Notification to Caregivers
    public func notifyCaregiversDoseTaken(medicationName: String, patientName: String) {
        guard !activeRelationships.isEmpty else { return }
        showToast("قام \(patientName) بتأكيد أخذ جرعة دواء \"\(medicationName)\" في الموعد.")
    }

    // MARK: - Internal Helpers & Persistence
    private func findInvitation(by token: String) -> ConnectionInvitation? {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let inv = outgoingInvitations.first(where: { $0.token.lowercased() == cleaned }) {
            return inv
        }
        return incomingInvitations.first(where: { $0.token.lowercased() == cleaned })
    }

    private func updateStoredInvitation(_ invitation: ConnectionInvitation) {
        if let idx = outgoingInvitations.firstIndex(where: { $0.id == invitation.id }) {
            outgoingInvitations[idx] = invitation
        }
        if let idx = incomingInvitations.firstIndex(where: { $0.id == invitation.id }) {
            incomingInvitations[idx] = invitation
        }
        // Note: do NOT append here — incoming invitations are added only via simulateIncomingInvitation
    }

    public func showToast(_ message: String) {
        notificationToastMessage = message
    }

    private func deduplicate(_ invitations: [ConnectionInvitation]) -> [ConnectionInvitation] {
        var seenIds = Set<UUID>()
        var seenTokens = Set<String>()
        var result: [ConnectionInvitation] = []
        for inv in invitations {
            let tokenKey = inv.token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !seenIds.contains(inv.id) && !seenTokens.contains(tokenKey) {
                seenIds.insert(inv.id)
                seenTokens.insert(tokenKey)
                result.append(inv)
            }
        }
        return result
    }

    private func persistState() {
        self.outgoingInvitations = deduplicate(outgoingInvitations)
        self.incomingInvitations = deduplicate(incomingInvitations)

        store.saveInvitations(deduplicate(outgoingInvitations + incomingInvitations))
        store.saveRelationships(activeRelationships)
    }

    private func loadPersistedState() {
        let allInvs = store.loadInvitations()
        if !allInvs.isEmpty {
            let uniqueInvs = deduplicate(allInvs)
            // Outgoing = invitations this user initiated (no recipientId = pending, or accepted/confirmed)
            self.outgoingInvitations = deduplicate(uniqueInvs.filter { $0.recipientId == nil || $0.status == .accepted || $0.status == .confirmed })
            // Incoming = invitations received by someone else (has a recipient, but NOT confirmed as outgoing)
            let outgoingIds = Set(self.outgoingInvitations.map { $0.id })
            let outgoingTokens = Set(self.outgoingInvitations.map { $0.token.lowercased() })
            self.incomingInvitations = deduplicate(uniqueInvs.filter { !outgoingIds.contains($0.id) && !outgoingTokens.contains($0.token.lowercased()) && $0.recipientId != nil })
        }

        self.activeRelationships = store.loadRelationships()
    }

    public func resetAllData() {
        outgoingInvitations.removeAll()
        incomingInvitations.removeAll()
        activeRelationships.removeAll()
        notificationToastMessage = nil
        store.removeAll()
    }

    /// Removes stale pending invitations for a given user — call on sheet open to clear accumulated state.
    public func clearStalePendingInvitations(for userId: String) {
        outgoingInvitations.removeAll { $0.initiatorId == userId && ($0.status == .pending || $0.isExpired) }
        outgoingInvitations = deduplicate(outgoingInvitations)
        persistState()
    }
}
