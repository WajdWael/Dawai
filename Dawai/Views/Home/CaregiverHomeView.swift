//
//  CaregiverHomeView.swift
//  Dawai
//
//  Caregiver Home View - Premium Apple Glass Mode Design
//  Decomposed into lightweight @ViewBuilder sub-expressions to ensure lightning-fast
//  Swift compiler type-checking without timeout or ambiguous init errors.
//

import SwiftUI

public struct CaregiverHomeView: View {
    let identity: UserIdentity
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var relationshipService = RelationshipService.shared

    // UC-2 Sheets State
    @State private var showingCreateInvitationSheet = false
    @State private var showingReceiveInvitationSheet = false
    @State private var showingSettingsSheet = false

    public init(identity: UserIdentity) {
        self.identity = identity
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        headerView
                        beneficiariesSection
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

    // MARK: - 2. Beneficiaries Section (UC-2 Link Patient & Caregiver)
    @ViewBuilder
    private var beneficiariesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("المستفيدين")
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
                    .accessibilityLabel("قبول دعوة مستفيد واردة")

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
                    .accessibilityLabel("إنشاء دعوة مستفيد جديد")
                }
            }

            // A. UC-2 S#6: Invitations Accepted by Patient (Pending Caregiver Confirmation)
            ForEach(relationshipService.outgoingInvitations.filter { $0.status == .accepted }) { invite in
                acceptedPatientCard(invite: invite)
            }

            // B. UC-2 S#7: Active Established Relationships (Real Linked Beneficiaries)
            ForEach(relationshipService.activeRelationships.filter { $0.caregiverId == identity.id }) { rel in
                activePatientRow(rel: rel)
            }

            // C. UC-2 S#5: Incoming Invitations to this Caregiver
            ForEach(relationshipService.incomingInvitations.filter { $0.status == .pending }) { incoming in
                incomingPatientCard(incoming: incoming)
            }

            // D. Pending Outgoing Invitations
            ForEach(relationshipService.outgoingInvitations.filter { $0.status == .pending }) { invite in
                pendingPatientCard(invite: invite)
            }

            // E. Default Demo Cards when no real connections added yet
            if relationshipService.activeRelationships.isEmpty &&
                relationshipService.outgoingInvitations.isEmpty &&
                relationshipService.incomingInvitations.isEmpty {
                ForEach(HomeMockData.beneficiaries.filter { !$0.isInvitation }) { item in
                    demoPatientRow(item: item)
                }
            }
        }
    }

    // MARK: - Beneficiary Cards Helpers
    @ViewBuilder
    private func acceptedPatientCard(invite: ConnectionInvitation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(invite.recipientDisplayName ?? "المستفيد")
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

            Text("قام المستفيد بقبول دعوتك. اضغط لتأكيد الاتصال وبدء متابعة جدول أدويته.")
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
    private func activePatientRow(rel: ActiveRelationship) -> some View {
        NavigationLink {
            CaregiverPatientDetailView(
                beneficiary: BeneficiarySummary(
                    name: rel.patientDisplayName,
                    hasDelayAlert: false,
                    delayNotice: nil,
                    scheduledTime: nil,
                    isInvitation: false
                )
            )
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text(rel.patientDisplayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)

                    Label("متصل • نشط", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }

                Spacer()

                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.dawaiGlassBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func incomingPatientCard(incoming: ConnectionInvitation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(incoming.initiatorDisplayName)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.primary)

                        Image(systemName: "circle.dotted")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.dawaiPrimary)
                    }
                    Text("أرسل لك دعوة ربط كمستفيد")
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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func pendingPatientCard(invite: ConnectionInvitation) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("دعوة مرسلة لمستفيد")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)

                    Image(systemName: "hourglass")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.dawaiPrimary)
                }

                Text("بانتظار قبول المستفيد • رمز الدعوة: \(invite.token)")
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
    private func demoPatientRow(item: BeneficiarySummary) -> some View {
        NavigationLink {
            CaregiverPatientDetailView(beneficiary: item)
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    if item.hasDelayAlert {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.yellow)
                    }

                    Text(item.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(cardBorderColor(hasDelayAlert: item.hasDelayAlert), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func cardBorderColor(hasDelayAlert: Bool) -> Color {
        if hasDelayAlert {
            return Color.orange.opacity(0.4)
        } else {
            return Color.dawaiGlassBorder
        }
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
                // Toast notification is managed by relationshipService
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
                // Toast notification is managed by relationshipService
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
                // Toast notification is managed by relationshipService
            }
        }
    }
}

#Preview {
    CaregiverHomeView(
        identity: UserIdentity(
            role: .caregiver,
            displayName: "سارة",
            keyFingerprint: "e28fa4891b0c9f1a"
        )
    )
    .environmentObject(AppState())
    .tint(Color.dawaiPrimary)
    .environment(\.layoutDirection, .rightToLeft)
}
