//
//  HomeView.swift
//  Dawai
//
//  Home Page Router - Routes to PatientHomeView or CaregiverHomeView
//  based on the user's role, preserving native Arabic RTL layout and
//  primary brand color #007B78.
//

import SwiftUI

public struct HomeView: View {
    let identity: UserIdentity
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var themeService = ThemeService.shared

    public init(identity: UserIdentity) {
        self.identity = identity
    }

    public var body: some View {
        Group {
            if identity.role == .patient {
                PatientHomeView(identity: identity)
            } else {
                CaregiverHomeView(identity: identity)
            }
        }
        .preferredColorScheme(themeService.colorScheme)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale.dawaiArabic)
        .onAppear {
            themeService.applyThemeToApp()
        }
        .sheet(isPresented: Binding(
            get: { appState.pendingInviteToken != nil },
            set: { if !$0 { appState.pendingInviteToken = nil } }
        )) {
            if let token = appState.pendingInviteToken {
                ReceiveInvitationSheet(currentUser: identity, prefilledToken: token)
                    .preferredColorScheme(themeService.colorScheme)
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.pendingDoseConfirmationMedicationId != nil },
            set: { if !$0 { appState.pendingDoseConfirmationMedicationId = nil } }
        )) {
            if let medId = appState.pendingDoseConfirmationMedicationId,
               let med = MedicationService.shared.medications.first(where: { $0.id == medId }) {
                DoseConfirmationSheet(medication: med, currentUser: identity) {
                    appState.pendingDoseConfirmationMedicationId = nil
                } onDismiss: {
                    appState.pendingDoseConfirmationMedicationId = nil
                }
                .preferredColorScheme(themeService.colorScheme)
            }
        }
        .sheet(item: $appState.pendingCaregiverBeneficiaryToOpen) { beneficiary in
            CaregiverPatientDetailView(beneficiary: beneficiary)
                .preferredColorScheme(themeService.colorScheme)
        }
    }
}

#Preview("Patient Home") {
    let mockPatient = UserIdentity(
        role: .patient,
        displayName: "سارة",
        keyFingerprint: "e28fa4891b0c9f1a"
    )
    return HomeView(identity: mockPatient)
        .environmentObject(AppState())
        .tint(Color.dawaiPrimary)
}

#Preview("Caregiver Home") {
    let mockCaregiver = UserIdentity(
        role: .caregiver,
        displayName: "أحمد",
        keyFingerprint: "e28fa4891b0c9f1a"
    )
    return HomeView(identity: mockCaregiver)
        .environmentObject(AppState())
        .tint(Color.dawaiPrimary)
}
