//
//  PatientHomeView.swift
//  Dawai
//
//  Patient Home View - Premium Apple Glass Mode Design
//  Decomposed into lightweight @ViewBuilder sub-expressions to ensure lightning-fast
//  Swift compiler type-checking without timeout errors.
//

import SwiftUI

public struct PatientHomeView: View {
    let identity: UserIdentity
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var relationshipService = RelationshipService.shared

    @State private var remainingDoses = HomeMockData.patientRemainingDoses
    @State private var activeMedication = HomeMockData.activeMedication
    @State private var upcomingDoses = HomeMockData.upcomingDoses

    // UC-2 Sheets State
    @State private var showingCreateInvitationSheet = false
    @State private var showingReceiveInvitationSheet = false
    @State private var showingSettingsSheet = false
    @State private var showingAddMedicationAlert = false

    public init(identity: UserIdentity) {
        self.identity = identity
    }

    public var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headerView
                    heroDoseCounterView
                    activeMedicationSection
                    upcomingDosesSection
                    caregiversSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

            // Notification Toast (UC-2 S#8)
            if let toastMessage = relationshipService.notificationToastMessage {
                NotificationToastView(message: toastMessage) {
                    relationshipService.dismissToast()
                }
            }
        }
        .background(Color.dawaiBackground.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
        .sheet(isPresented: $showingCreateInvitationSheet) {
            CreateInvitationSheet(currentUser: identity)
        }
        .sheet(isPresented: $showingReceiveInvitationSheet) {
            ReceiveInvitationSheet(currentUser: identity)
        }
        .sheet(isPresented: $showingSettingsSheet) {
            IdentityDetailsSheet(identity: identity)
        }
        .alert("إضافة دواء جديد", isPresented: $showingAddMedicationAlert) {
            Button("حسناً", role: .cancel) {}
        } message: {
            Text("سيتم تفعيل هذه الميزة قريباً مع ربط الواجهة الخلفية.")
        }
    }

    // MARK: - 1. Top Header View
    @ViewBuilder
    private var headerView: some View {
        HStack(alignment: .center) {
            Text(identity.displayName)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                showingSettingsSheet = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.dawaiPrimary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().stroke(Color.dawaiGlassBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("الإعدادات وتفاصيل الهوية")
        }
        .padding(.top, 8)
    }

    // MARK: - 2. Hero Dose Counter Card
    @ViewBuilder
    private var heroDoseCounterView: some View {
        HStack {
            Spacer()
            Text("بقي \(remainingDoses) جرعات لليوم")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.dawaiPrimary,
                            Color.dawaiPrimary.opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - 3. Active Medication Section
    @ViewBuilder
    private var activeMedicationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ادويتي")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    showingAddMedicationAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.dawaiPrimary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(
                            Circle().stroke(Color.dawaiGlassBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("إضافة دواء جديد")
            }

            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    // Pill Icon Frame on RIGHT (FIRST in HStack)
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.dawaiPrimary.opacity(0.12))
                            .frame(width: 68, height: 68)

                        Image(systemName: "pill.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.dawaiPrimary)
                            .rotationEffect(.degrees(-45))
                    }

                    // Details in CENTER
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeMedication.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.primary)

                        Text(activeMedication.dosage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(activeMedication.timeString)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.dawaiPrimary)
                    }

                    Spacer()

                    // Edit Button on LEFT
                    Button {
                        // Edit action
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // Dose Confirmation Action Button
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        activeMedication.isTaken.toggle()
                        if activeMedication.isTaken && remainingDoses > 0 {
                            remainingDoses -= 1
                        } else if !activeMedication.isTaken {
                            remainingDoses += 1
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if activeMedication.isTaken {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                            Text("تم أخذ الدواء")
                                .font(.system(size: 18, weight: .bold))
                        } else {
                            Text("اخذت الدواء")
                                .font(.system(size: 18, weight: .bold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(activeMedication.isTaken ? Color.green : Color.dawaiPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.dawaiGlassBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - 4. Upcoming Doses Section
    @ViewBuilder
    private var upcomingDosesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("باقي اليوم")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                ForEach(upcomingDoses.indices, id: \.self) { index in
                    let dose = upcomingDoses[index]
                    HStack {
                        HStack(spacing: 8) {
                            Text(dose.name)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.primary)

                            Text(dose.timeString)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            // Edit
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(
                                    Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)

                    if index < upcomingDoses.count - 1 {
                        Divider()
                            .padding(.horizontal, 14)
                    }
                }
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.dawaiGlassBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - 5. Caregivers Section (UC-2 Link Patient & Caregiver)
    @ViewBuilder
    private var caregiversSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("مقدمي الرعاية")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        showingReceiveInvitationSheet = true
                    } label: {
                        Image(systemName: "envelope.badge")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.dawaiPrimary)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle().stroke(Color.dawaiGlassBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("قبول دعوة اتصال واردة")

                    Button {
                        showingCreateInvitationSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.dawaiPrimary)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle().stroke(Color.dawaiGlassBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("إنشاء دعوة مقدم رعاية")
                }
            }

            // A. UC-2 S#6: Invitations Accepted by Caregiver (Pending Patient Confirmation)
            ForEach(relationshipService.outgoingInvitations.filter { $0.status == .accepted }) { invite in
                acceptedCaregiverCard(invite: invite)
            }

            // B. UC-2 S#7: Active Established Relationships
            ForEach(relationshipService.activeRelationships.filter { $0.patientId == identity.id }) { rel in
                activeCaregiverCard(rel: rel)
            }

            // C. UC-2 S#5: Incoming Invitations to this Patient
            ForEach(relationshipService.incomingInvitations.filter { $0.status == .pending }) { incoming in
                incomingCaregiverCard(incoming: incoming)
            }

            // D. Pending Outgoing Invitations
            ForEach(relationshipService.outgoingInvitations.filter { $0.status == .pending }) { invite in
                pendingCaregiverCard(invite: invite)
            }

            // E. Fallback Card when empty
            if relationshipService.activeRelationships.isEmpty &&
                relationshipService.outgoingInvitations.isEmpty &&
                relationshipService.incomingInvitations.isEmpty {
                fallbackCaregiverCard
            }
        }
    }

    // MARK: - Caregiver Cards Helpers
    @ViewBuilder
    private func acceptedCaregiverCard(invite: ConnectionInvitation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(invite.recipientDisplayName ?? "مقدم الرعاية")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)

                Spacer()

                Text("قبل الدعوة")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12), in: Capsule())
            }

            Text("قام الطرف الآخر بقبول دعوتك. اضغط لتأكيد الاتصال وتفعيل العلاقة.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Button {
                handleConfirmConnection(invite: invite)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                    Text("تأكيد الارتباط وتفعيله (S#6: Confirm)")
                        .font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.dawaiPrimary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.dawaiPrimaryBorder, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func activeCaregiverCard(rel: ActiveRelationship) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(rel.caregiverDisplayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)

                    Label("نشط • متصل", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }

                Text("تم تفعيل صلاحيات متابعة الجرعات والتنبيهات")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func incomingCaregiverCard(incoming: ConnectionInvitation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(incoming.initiatorDisplayName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)

                        Image(systemName: "circle.dotted")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.dawaiPrimary)
                    }

                    Text("أرسل لك دعوة ربط كمقدم رعاية")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    handleAcceptInvitation(incoming: incoming)
                } label: {
                    Text("قبول")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.dawaiPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    handleRejectInvitation(incoming: incoming)
                } label: {
                    Text("رفض")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(.ultraThinMaterial)
                        .foregroundStyle(Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func pendingCaregiverCard(invite: ConnectionInvitation) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("دعوة اتصال مرسلة")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)

                    Image(systemName: "hourglass")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.dawaiPrimary)
                }

                Text("بانتظار قبول الطرف الآخر • رمز الدعوة: \(invite.token)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var fallbackCaregiverCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("سارة")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)

                    Image(systemName: "circle.dotted")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.dawaiPrimary)
                }

                Text("تم ارسال الدعوة في انتظار القبول")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
        )
    }

    // MARK: - UC-2 Actions (Explicit Void returns to avoid Swift closure generic conflicts)
    private func handleConfirmConnection(invite: ConnectionInvitation) {
        withAnimation {
            do {
                _ = try relationshipService.confirmConnection(
                    invitationId: invite.id,
                    initiator: identity
                )
            } catch {
                // Toast notification managed by relationshipService
            }
        }
    }

    private func handleAcceptInvitation(incoming: ConnectionInvitation) {
        withAnimation {
            do {
                _ = try relationshipService.acceptInvitation(
                    token: incoming.token,
                    recipient: identity
                )
            } catch {
                // Toast notification managed by relationshipService
            }
        }
    }

    private func handleRejectInvitation(incoming: ConnectionInvitation) {
        withAnimation {
            do {
                try relationshipService.rejectInvitation(
                    token: incoming.token,
                    recipient: identity
                )
            } catch {
                // Toast notification managed by relationshipService
            }
        }
    }
}

#Preview {
    PatientHomeView(
        identity: UserIdentity(
            role: .patient,
            displayName: "سارة",
            keyFingerprint: "e28fa4891b0c9f1a"
        )
    )
    .environmentObject(AppState())
    .environment(\.layoutDirection, .rightToLeft)
}
