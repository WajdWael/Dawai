//
//  HomeView.swift
//  Dawai
//
//  Home Page Router - Routes to PatientHomeView or CaregiverHomeView
//  based on the user's role, preserving native Arabic RTL layout and
//  primary brand color #007B78.
//

import SwiftUI

private enum HomeModalSheet: Identifiable {
    case invite(String)
    case doseConfirmation(UUID)

    var id: String {
        switch self {
        case .invite(let token):
            return "invite_\(token)"
        case .doseConfirmation(let medId):
            return "dose_\(medId.uuidString)"
        }
    }
}

public struct HomeView: View {
    let identity: UserIdentity
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var themeService = ThemeService.shared

    public init(identity: UserIdentity) {
        self.identity = identity
    }

    private var activeModalSheet: Binding<HomeModalSheet?> {
        Binding(
            get: {
                if let token = appState.pendingInviteToken {
                    return .invite(token)
                }
                if let medId = appState.pendingDoseConfirmationMedicationId {
                    return .doseConfirmation(medId)
                }
                return nil
            },
            set: { newValue in
                if newValue == nil {
                    appState.pendingInviteToken = nil
                    appState.pendingDoseConfirmationMedicationId = nil
                    appState.pendingDoseConfirmationSlotMinutes = nil
                }
            }
        )
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
        .environment(\.dawaiFontScale, themeService.fontScale)
        .environment(\.dynamicTypeSize, themeService.dynamicTypeSize)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale.dawaiArabic)
        .onAppear {
            themeService.applyThemeToApp()
            CloudKitSyncManager.shared.startPeriodicSync()
            Task {
                await MedicationService.shared.requestNotificationPermissionIfNeeded()
                if identity.role == .patient {
                    _ = await MedicationAlarmService.shared.requestAuthorizationIfNeeded()
                }
            }
        }
        .sheet(item: activeModalSheet) { sheet in
            switch sheet {
            case .invite(let token):
                ReceiveInvitationSheet(currentUser: identity, prefilledToken: token)
                    .preferredColorScheme(themeService.colorScheme)
            case .doseConfirmation(let medId):
                if let med = MedicationService.shared.medications.first(where: { $0.id == medId })
                    ?? MedicationService.shared.allMedications.first(where: { $0.id == medId }) {
                    DoseConfirmationSheet(
                        medication: med,
                        slotMinutes: appState.pendingDoseConfirmationSlotMinutes,
                        currentUser: identity
                    ) {
                        appState.pendingDoseConfirmationMedicationId = nil
                        appState.pendingDoseConfirmationSlotMinutes = nil
                    } onDismiss: {
                        appState.pendingDoseConfirmationMedicationId = nil
                        appState.pendingDoseConfirmationSlotMinutes = nil
                    }
                    .preferredColorScheme(themeService.colorScheme)
                }
            }
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
