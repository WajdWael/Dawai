//
//  CaregiverHomeView.swift
//  Dawai
//
//  Caregiver Home View - Native iOS System List with Apple Glass Aesthetics
//  Decomposed into lightweight @ViewBuilder sub-expressions to ensure lightning-fast
//  Swift compiler type-checking without timeout or ambiguous init errors.
//

import SwiftUI

public struct CaregiverHomeView: View {
    let identity: UserIdentity
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var relationshipService = RelationshipService.shared
    @ObservedObject private var medicationService = MedicationService.shared
    @ObservedObject private var themeService = ThemeService.shared

    // UC-2 Sheets State
    @State private var showingCreateInvitationSheet = false
    @State private var showingSettingsSheet = false
    @State private var showingReportSheet = false

    public init(identity: UserIdentity) {
        self.identity = identity
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Native iOS System List
                List {
                    // Top Header unstyled row inside the List
                    Section {
                        headerView
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    // Actionable Connection Invitations (if any)
                    invitationsSection

                    // Actionable Medication Deletion Requests (UC-11)
                    if !medicationService.pendingDeletionRequests.isEmpty {
                        pendingDeletionSection
                    }

                    // Beneficiaries System Inset Grouped List
                    beneficiariesSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.dawaiBackground.ignoresSafeArea())

                // Notification Toast (UC-2 S#8 & UC-11)
                if let toastMessage = medicationService.toastMessage ?? relationshipService.notificationToastMessage {
                    NotificationToastView(message: toastMessage) {
                        medicationService.dismissToast()
                        relationshipService.dismissToast()
                    }
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale.dawaiArabic)
            .sheet(isPresented: $showingCreateInvitationSheet) {
                CreateInvitationSheet(currentUser: identity)
                    .preferredColorScheme(ThemeService.shared.colorScheme)
            }
            .sheet(isPresented: $showingSettingsSheet) {
                IdentityDetailsSheet(identity: identity)
                    .preferredColorScheme(themeService.colorScheme)
            }
            .sheet(isPresented: $showingReportSheet) {
                AdherenceReportView(currentUser: identity)
                    .preferredColorScheme(themeService.colorScheme)
            }
            .onAppear {
                themeService.applyThemeToApp()
            }
            .preferredColorScheme(themeService.colorScheme)
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

            // Reports Button (UC-7 S#1: Application navigation access for Caregivers)
            Button {
                showingReportSheet = true
            } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.dawaiPrimary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().stroke(Color.dawaiGlassBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("تقارير الالتزام الدوائي")

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
        .padding(.top, 4)
    }

    // MARK: - 2. Section Header
    @ViewBuilder
    private var sectionHeaderView: some View {
        HStack {
            Text("المستفيدين")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
                .textCase(nil)

            Spacer()

            Button {
                showingCreateInvitationSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.dawaiPrimary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().stroke(Color.dawaiGlassBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("إنشاء دعوة مستفيد جديد")
        }
    }

    // MARK: - 2.5 Actionable Medication Deletion Requests (UC-11)
    @ViewBuilder
    private var pendingDeletionSection: some View {
        Section {
            ForEach(medicationService.pendingDeletionRequests) { req in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("طلب حذف: \(req.medicationName)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.primary)
                            Text("من: \(req.patientDisplayName) • \(req.dosage)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 10, weight: .bold))
                            Text("بانتظار موافقتك")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color.dawaiWarning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.dawaiWarningBackground, in: Capsule())
                    }

                    HStack(spacing: 12) {
                        Button {
                            withAnimation {
                                medicationService.approveDeletionRequest(requestId: req.id)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text("قبول وحذف")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.12))
                            .foregroundStyle(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation {
                                medicationService.rejectDeletionRequest(requestId: req.id)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 12, weight: .bold))
                                Text("رفض والاحتفاظ")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.dawaiPrimary.opacity(0.12))
                            .foregroundStyle(Color.dawaiPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(rowBackground(hasDelayAlert: true))
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .foregroundStyle(Color.dawaiWarning)
                Text("طلبات حذف الأدوية من المستفيدين")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - 3. Beneficiaries Section (Native iOS System List)
    @ViewBuilder
    private var beneficiariesSection: some View {
        let activeRels = relationshipService.activeRelationships.filter { $0.caregiverId == identity.id }
        let demoItems = HomeMockData.beneficiaries.filter { !$0.isInvitation }

        Section {
            if !activeRels.isEmpty {
                ForEach(activeRels, id: \.id) { rel in
                    activePatientRow(rel: rel)
                        .listRowBackground(rowBackground(hasDelayAlert: medicationService.hasMissedDosesToday))
                }
            } else if relationshipService.outgoingInvitations.isEmpty && relationshipService.incomingInvitations.isEmpty {
                // All beneficiaries together in the same system list
                ForEach(demoItems, id: \.id) { item in
                    demoItemRow(item: item)
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.badge.gearshape")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.secondary)
                        Text("بانتظار اكتمال الارتباط")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
                .listRowBackground(glassRowBackground)
            }
        } header: {
            sectionHeaderView
        }
    }

    // MARK: - Demo Beneficiary Row
    @ViewBuilder
    private func demoItemRow(item: BeneficiarySummary) -> some View {
        NavigationLink {
            CaregiverPatientDetailView(beneficiary: item)
        } label: {
            if item.hasDelayAlert {
                latePatientRow(item: item)
            } else {
                demoPatientRow(item: item)
            }
        }
        .listRowBackground(rowBackground(hasDelayAlert: item.hasDelayAlert))
    }

    // MARK: - Row Background Helpers
    private func rowBackground(hasDelayAlert: Bool) -> some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(
                hasDelayAlert
                    ? Color.dawaiWarningBackground.opacity(0.9)
                    : Color(uiColor: .secondarySystemGroupedBackground).opacity(0.6)
            )
            .overlay(
                hasDelayAlert
                    ? Color.dawaiWarningBorder
                    : Color.clear
            )
    }

    private var glassRowBackground: some View {
        rowBackground(hasDelayAlert: false)
    }

    private var alertRowBackground: some View {
        rowBackground(hasDelayAlert: true)
    }

    // MARK: - Late Patient Row Content (Refined Warm Amber Alert Row)
    @ViewBuilder
    private func latePatientRow(item: BeneficiarySummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.dawaiWarning)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)

                if let notice = item.delayNotice {
                    Text(notice)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.dawaiWarning)
                }
            }

            Spacer()

            Text("متأخر")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.dawaiWarning)
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(Color.dawaiWarningBadgeBackground, in: Capsule())
                .overlay(
                    Capsule().stroke(Color.dawaiWarningBorder, lineWidth: 0.8)
                )
        }
        .padding(.vertical, 4)
    }

    // MARK: - Demo Patient Row Content (Clean Name Only, No Redundant Subtitle)
    @ViewBuilder
    private func demoPatientRow(item: BeneficiarySummary) -> some View {
        HStack {
            Text(item.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.vertical, 6)
    }

    // MARK: - Active Patient Row (Connected Glass Row)
    @ViewBuilder
    private func activePatientRow(rel: ActiveRelationship) -> some View {
        let hasDelay = medicationService.hasMissedDosesToday
        let missedMed = medicationService.missedMedicationsToday.first
        let delayNoticeText = missedMed != nil ? "30 د تأخير، \(missedMed!.name)" : nil
        let summary = BeneficiarySummary(
            id: rel.id,
            name: rel.patientDisplayName,
            hasDelayAlert: hasDelay,
            delayNotice: delayNoticeText,
            scheduledTime: missedMed?.timeString,
            isInvitation: false,
            delayedMedicationName: missedMed?.name,
            delayedDosage: missedMed?.dosage,
            phoneNumber: "0501234567"
        )

        NavigationLink {
            CaregiverPatientDetailView(beneficiary: summary)
        } label: {
            if hasDelay {
                latePatientRow(item: summary)
            } else {
                HStack(spacing: 12) {
                    Text(rel.patientDisplayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("نشط")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.dawaiTaken)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.dawaiTakenBadgeBackground, in: Capsule())
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - 4. Invitations Section (System List)
    @ViewBuilder
    private var invitationsSection: some View {
        let acceptedInvites = deduplicateInvitations(relationshipService.outgoingInvitations.filter { $0.status == .accepted })
        let incomingInvites = deduplicateInvitations(relationshipService.incomingInvitations.filter { $0.status == .pending })
        let pendingInvites = deduplicateInvitations(relationshipService.outgoingInvitations.filter { $0.status == .pending })

        if !acceptedInvites.isEmpty || !incomingInvites.isEmpty || !pendingInvites.isEmpty {
            Section {
                ForEach(acceptedInvites) { invite in
                    acceptedPatientCard(invite: invite)
                }

                ForEach(incomingInvites) { incoming in
                    incomingPatientCard(incoming: incoming)
                }

                ForEach(pendingInvites) { invite in
                    pendingPatientCard(invite: invite)
                }
            } header: {
                Text("طلبات الارتباط والدعوات")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }

    private func deduplicateInvitations(_ list: [ConnectionInvitation]) -> [ConnectionInvitation] {
        var seen = Set<String>()
        return list.filter { inv in
            let key = inv.token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return seen.insert(key).inserted
        }
    }

    // MARK: - Beneficiary Cards Helpers (Native iOS System List Rows)
    @ViewBuilder
    private func acceptedPatientCard(invite: ConnectionInvitation) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.dawaiTaken.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dawaiTaken)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cleanDisplayName(invite.recipientDisplayName ?? "المستفيد"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("تم القبول • كود: \(cleanToken(invite.token))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    handleConfirmConnection(invite: invite)
                } label: {
                    Text("تأكيد")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.dawaiPrimary, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        relationshipService.rejectAcceptedInvitation(invitationId: invite.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("رفض الدعوة")
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    relationshipService.rejectAcceptedInvitation(invitationId: invite.id)
                }
            } label: {
                Label("رفض", systemImage: "xmark")
            }
        }
    }

    @ViewBuilder
    private func incomingPatientCard(incoming: ConnectionInvitation) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.dawaiPrimary.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dawaiPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cleanDisplayName(incoming.initiatorDisplayName))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("طلب ارتباط • كود: \(cleanToken(incoming.token))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    handleAcceptInvitation(incoming: incoming)
                } label: {
                    Text("قبول")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.dawaiPrimary, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    handleRejectInvitation(incoming: incoming)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("رفض الدعوة")
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                handleRejectInvitation(incoming: incoming)
            } label: {
                Label("رفض", systemImage: "xmark")
            }
        }
    }

    @ViewBuilder
    private func pendingPatientCard(invite: ConnectionInvitation) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .systemGray5))
                    .frame(width: 36, height: 36)
                Image(systemName: "envelope.badge")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.dawaiPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("دعوة مستفيد")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("معلقة • كود: \(cleanToken(invite.token))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    UIPasteboard.general.string = invite.token
                    relationshipService.notificationToastMessage = "تم نسخ رمز الدعوة بنجاح"
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text("نسخ")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.dawaiPrimary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.dawaiPrimary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("نسخ رمز الدعوة")

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        relationshipService.cancelOutgoingInvitation(invitationId: invite.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("إلغاء الدعوة")
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    relationshipService.cancelOutgoingInvitation(invitationId: invite.id)
                }
            } label: {
                Label("إلغاء", systemImage: "trash")
            }
        }
    }

    private func cleanDisplayName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "(مقدم رعاية)", with: "")
            .replacingOccurrences(of: "(مستفيد)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanToken(_ token: String) -> String {
        let raw = token.replacingOccurrences(of: "-", with: "").uppercased()
        if raw.count >= 8 {
            return "\(raw.prefix(4))-\(raw.dropFirst(4).prefix(4))"
        }
        return raw
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
