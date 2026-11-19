//
//  AppState.swift
//  Dawai
//
//  Use-Case 1 (UC-1): Application Root State
//

import Foundation
import SwiftUI
import Combine

/// Global application state managing identity readiness and routing between onboarding and Home.
@MainActor
public final class AppState: ObservableObject {
    /// True when anonymous application identity setup is complete and credentials exist.
    @Published public var isIdentified: Bool = false
    
    /// The currently active anonymous user identity.
    @Published public var currentIdentity: UserIdentity?

    /// Pending invitation token received via deep link (UC-2 S#4)
    @Published public var pendingInviteToken: String? = nil

    /// Pending medication ID for dose confirmation via notification tap (UC-4 S#4)
    @Published public var pendingDoseConfirmationMedicationId: UUID? = nil

    /// Optional scheduled dose slot (minutes from midnight) when opening a multi-dose medication from notification tap.
    @Published public var pendingDoseConfirmationSlotMinutes: Int? = nil

    /// Pending beneficiary to navigate to upon tapping missed-dose notification (UC-5 S#5)
    @Published public var pendingCaregiverBeneficiaryToOpen: BeneficiarySummary? = nil

    /// Triggers the dose confirmation screen for a specific medication dose (UC-4 S#4 & S#5)
    public func openDoseConfirmation(for medicationId: UUID, slotMinutes: Int? = nil) {
        withAnimation(.easeInOut(duration: 0.3)) {
            self.pendingDoseConfirmationSlotMinutes = slotMinutes
            self.pendingDoseConfirmationMedicationId = medicationId
        }
    }

    /// Triggers navigation to patient detail screen for missed-dose review (UC-5 S#5)
    public func openCaregiverPatientDetail(for beneficiary: BeneficiarySummary) {
        withAnimation(.easeInOut(duration: 0.3)) {
            self.pendingCaregiverBeneficiaryToOpen = beneficiary
        }
    }
    
    private let identityService: IdentityService

    public init() {
        self.identityService = IdentityService.shared
        loadExistingIdentity()
    }

    public init(identityService: IdentityService) {
        self.identityService = identityService
        loadExistingIdentity()
    }

    /// Loads persisted identity if available.
    public func loadExistingIdentity() {
        if let identity = identityService.fetchCurrentIdentity() {
            self.currentIdentity = identity
            self.isIdentified = true
        } else {
            self.currentIdentity = nil
            self.isIdentified = false
        }
    }

    /// Called upon successful completion of UC-1 (S#7: Redirects the user to the Home Page).
    public func completeSetup(identity: UserIdentity) {
        // Every new user starts from a 100% clean, empty slate before saving the new identity.
        LocalDataStore.resetAllUserData()
        // A pending invitation link opened before onboarding finished is kept, so it is reviewed right after setup.
        pendingDoseConfirmationMedicationId = nil
        pendingDoseConfirmationSlotMinutes = nil
        pendingCaregiverBeneficiaryToOpen = nil

        _ = KeychainService.shared.saveUserIdentity(identity)
        withAnimation(.easeInOut(duration: 0.35)) {
            self.currentIdentity = identity
            self.isIdentified = true
        }
        MedicationService.shared.loadPersistedMedications()
        AdherenceService.shared.loadRecords()
        CloudKitSyncManager.shared.startPeriodicSync()
    }

    /// Switches between Patient and Caregiver accounts on the same device without wiping stored data.
    public func switchAccountRole(to targetRole: UserRole, customName: String? = nil) {
        let trimmedCustom = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nextIdentity: UserIdentity

        if let existing = KeychainService.shared.loadUserIdentity(forRole: targetRole) {
            if !trimmedCustom.isEmpty {
                nextIdentity = UserIdentity(
                    id: existing.id,
                    role: targetRole,
                    displayName: trimmedCustom,
                    createdAt: existing.createdAt,
                    keyFingerprint: existing.keyFingerprint
                )
            } else {
                nextIdentity = existing
            }
        } else if targetRole == .caregiver,
                  let currentId = currentIdentity?.id,
                  let rel = RelationshipService.shared.activeCaregiver(forPatient: currentId) {
            nextIdentity = UserIdentity(
                id: rel.caregiverId,
                role: .caregiver,
                displayName: trimmedCustom.isEmpty ? rel.caregiverDisplayName : trimmedCustom,
                keyFingerprint: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16).description
            )
        } else if targetRole == .patient,
                  let currentId = currentIdentity?.id,
                  let rel = RelationshipService.shared.activeRelationships.first(where: { $0.caregiverId == currentId && $0.isActive }) {
            nextIdentity = UserIdentity(
                id: rel.patientId,
                role: .patient,
                displayName: trimmedCustom.isEmpty ? rel.patientDisplayName : trimmedCustom,
                keyFingerprint: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16).description
            )
        } else {
            let fallbackName = !trimmedCustom.isEmpty ? trimmedCustom : (targetRole == .caregiver ? "سارة" : "عمر")
            nextIdentity = KeychainService.shared.loadOrCreateIdentity(forRole: targetRole, defaultName: fallbackName)
        }

        _ = KeychainService.shared.saveUserIdentity(nextIdentity)
        withAnimation(.easeInOut(duration: 0.3)) {
            self.currentIdentity = nextIdentity
            self.isIdentified = true
        }
        MedicationService.shared.loadPersistedMedications()
        AdherenceService.shared.loadRecords()
        CloudKitSyncManager.shared.startPeriodicSync()
    }

    /// Clears the identity and every piece of locally stored user data, returning the app to a first-launch state.
    /// Also publishes relationshipEnd events to CloudKit so any linked counterpart device deletes the link immediately.
    public func resetIdentityAndAllData() {
        // 1. Notify CloudKit that all active relationships for this user have ended
        let activeRels = RelationshipService.shared.activeRelationships
        for rel in activeRels {
            CloudKitSyncManager.shared.publishRelationshipEnded(rel)
        }

        LocalDataStore.resetAllUserData()
        identityService.resetIdentity()
        pendingInviteToken = nil
        pendingDoseConfirmationMedicationId = nil
        pendingDoseConfirmationSlotMinutes = nil
        pendingCaregiverBeneficiaryToOpen = nil
        withAnimation(.easeInOut(duration: 0.35)) {
            self.currentIdentity = nil
            self.isIdentified = false
        }
    }
}
