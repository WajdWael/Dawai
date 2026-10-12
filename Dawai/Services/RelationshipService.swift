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

    private let storageKeyInvitations = "dawai_stored_invitations_v1"
    private let storageKeyRelationships = "dawai_stored_relationships_v1"

    public init() {
        loadPersistedState()
    }

    // MARK: - S#2: Create a Secure Invitation
    public func createInvitation(initiator: UserIdentity) -> ConnectionInvitation {
        let invitation = ConnectionInvitation(
            initiatorId: initiator.id,
            initiatorDisplayName: initiator.displayName,
            initiatorRole: initiator.role,
            initiatorKeyFingerprint: initiator.keyFingerprint
        )
        
        outgoingInvitations.append(invitation)
        persistState()
        return invitation
    }

    // MARK: - S#4: Validate Invitation (Link Opened)
    @discardableResult
    public func validateInvitation(token: String, recipient: UserIdentity) throws -> ConnectionInvitation {
        // Look up token in outgoing/shared invitations
        guard let invitation = findInvitation(by: token) else {
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

        // Check if relationship already active
        let alreadyActive = activeRelationships.contains { rel in
            (rel.patientId == recipient.id && rel.caregiverId == invitation.initiatorId) ||
            (rel.caregiverId == recipient.id && rel.patientId == invitation.initiatorId)
        }
        if alreadyActive {
            throw InvitationError.relationshipAlreadyExists
        }

        return invitation
    }

    // MARK: - S#5: Recipient Reviews and Accepts Invitation
    @discardableResult
    public func acceptInvitation(token: String, recipient: UserIdentity) throws -> ConnectionInvitation {
        var invitation = try validateInvitation(token: token, recipient: recipient)

        guard invitation.status == .pending else {
            throw InvitationError.invitationAlreadyProcessed
        }

        invitation.status = .accepted
        invitation.recipientId = recipient.id
        invitation.recipientDisplayName = recipient.displayName
        invitation.recipientRole = recipient.role
        invitation.recipientKeyFingerprint = recipient.keyFingerprint

        updateStoredInvitation(invitation)
        
        // S#5: Notify initiator that recipient accepted
        showToast("قام \(recipient.displayName) بقبول دعوتك! يرجى تأكيد الاتصال.")
        persistState()

        return invitation
    }

    // MARK: - Recipient Rejects Invitation
    public func rejectInvitation(token: String, recipient: UserIdentity) throws {
        guard var invitation = findInvitation(by: token) else {
            throw InvitationError.tokenNotFound
        }

        invitation.status = .rejected
        invitation.recipientId = recipient.id
        invitation.recipientDisplayName = recipient.displayName
        invitation.recipientRole = recipient.role

        updateStoredInvitation(invitation)
        showToast("تم رفض الدعوة من قبل \(recipient.displayName).")
        persistState()
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

        guard invitation.status == .accepted else {
            throw InvitationError.invitationNotAcceptedYet
        }

        guard let recipientId = invitation.recipientId,
              let recipientName = invitation.recipientDisplayName else {
            throw InvitationError.invitationNotAcceptedYet
        }

        // Mark as confirmed (S#6)
        invitation.status = .confirmed
        outgoingInvitations[index] = invitation

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

        let relationship = ActiveRelationship(
            invitationId: invitation.id,
            patientId: patientId,
            patientDisplayName: patientName,
            caregiverId: caregiverId,
            caregiverDisplayName: caregiverName,
            establishedAt: Date(),
            isActive: true
        )

        activeRelationships.append(relationship)

        // S#8: Notify both users
        showToast("تم إنشاء الاتصال بنجاح وتفعيله بين \(patientName) و \(caregiverName)!")
        persistState()

        return relationship
    }

    // MARK: - Developer / Testing Simulation Helper
    /// Creates a simulated incoming invitation or marks an outgoing one as accepted for smooth demo testing
    public func simulateRecipientAcceptance(for invitationId: UUID, simulatedRecipientName: String = "سارة") {
        guard let index = outgoingInvitations.firstIndex(where: { $0.id == invitationId }) else { return }
        
        let oppositeRole: UserRole = outgoingInvitations[index].initiatorRole == .patient ? .caregiver : .patient
        outgoingInvitations[index].status = .accepted
        outgoingInvitations[index].recipientId = "dawai_anon_sim_\(UUID().uuidString.prefix(6))"
        outgoingInvitations[index].recipientDisplayName = simulatedRecipientName
        outgoingInvitations[index].recipientRole = oppositeRole
        outgoingInvitations[index].recipientKeyFingerprint = "7a8b9c0d1e2f3a4b"

        showToast("قام \(simulatedRecipientName) بقبول الدعوة! يمكنك الآن تأكيد الاتصال.")
        persistState()
    }

    public func simulateIncomingInvitation(fromName: String, fromRole: UserRole, currentRecipient: UserIdentity) -> ConnectionInvitation {
        let invitation = ConnectionInvitation(
            initiatorId: "dawai_anon_sim_\(UUID().uuidString.prefix(6))",
            initiatorDisplayName: fromName,
            initiatorRole: fromRole,
            initiatorKeyFingerprint: "9f8e7d6c5b4a3a2b",
            status: .pending
        )
        
        incomingInvitations.append(invitation)
        showToast("وصلتك دعوة اتصال جديدة من \(fromName) (\(fromRole.titleArabic))")
        persistState()
        return invitation
    }

    public func dismissToast() {
        notificationToastMessage = nil
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
        } else {
            incomingInvitations.append(invitation)
        }
    }

    private func showToast(_ message: String) {
        notificationToastMessage = message
    }

    private func persistState() {
        do {
            let invData = try JSONEncoder().encode(outgoingInvitations + incomingInvitations)
            UserDefaults.standard.set(invData, forKey: storageKeyInvitations)

            let relData = try JSONEncoder().encode(activeRelationships)
            UserDefaults.standard.set(relData, forKey: storageKeyRelationships)
        } catch {
            print("Failed to persist relationship state: \(error)")
        }
    }

    private func loadPersistedState() {
        if let invData = UserDefaults.standard.data(forKey: storageKeyInvitations),
           let allInvs = try? JSONDecoder().decode([ConnectionInvitation].self, from: invData) {
            self.outgoingInvitations = allInvs.filter { $0.recipientId == nil || $0.status == .accepted || $0.status == .confirmed }
            self.incomingInvitations = allInvs.filter { $0.recipientId != nil }
        }

        if let relData = UserDefaults.standard.data(forKey: storageKeyRelationships),
           let rels = try? JSONDecoder().decode([ActiveRelationship].self, from: relData) {
            self.activeRelationships = rels
        }
    }

    public func resetForTesting() {
        outgoingInvitations.removeAll()
        incomingInvitations.removeAll()
        activeRelationships.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKeyInvitations)
        UserDefaults.standard.removeObject(forKey: storageKeyRelationships)
    }
}
