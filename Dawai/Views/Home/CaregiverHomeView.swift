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
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var relationshipService = RelationshipService.shared
    @ObservedObject private var medicationService = MedicationService.shared
    @ObservedObject private var themeService = ThemeService.shared
    @ObservedObject private var demoMode = DemoModeService.shared
    @State private var showingCreateInvitationSheet = false
    @State private var showingReceiveInvitationSheet = false
    @State private var showingSettingsSheet = false
    @State private var showingReportSheet = false
    @State private var navigationPath: [BeneficiarySummary] = []

    public init(identity: UserIdentity) {
        self.identity = identity
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
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
                    if !medicationService.deletionRequests(forCaregiver: identity.id).isEmpty {
                        pendingDeletionSection
                    }

                    // Beneficiaries System Inset Grouped List
                    beneficiariesSection
                }
                .listStyle(.insetGrouped)
                .compactListTopMargin()
                .scrollContentBackground(.hidden)
                .background(Color.dawaiBackground.ignoresSafeArea())
                .refreshable {
                    await CloudKitSyncManager.shared.syncNow(silent: false)
                }

                // Notification Toast (UC-2 S#8 & UC-11)
                if let toastMessage = medicationService.toastMessage ?? relationshipService.notificationToastMessage {
                    NotificationToastView(message: toastMessage) {
                        medicationService.dismissToast()
                        relationshipService.dismissToast()
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale.dawaiArabic)
            .sheet(isPresented: $showingCreateInvitationSheet) {
                CreateInvitationSheet(currentUser: identity)
                    .preferredColorScheme(ThemeService.shared.colorScheme)
            }
            .sheet(isPresented: $showingReceiveInvitationSheet) {
                ReceiveInvitationSheet(currentUser: identity)
                    .preferredColorScheme(themeService.colorScheme)
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
                consumePendingBeneficiaryIfNeeded()
                Task {
                    await medicationService.requestNotificationPermissionIfNeeded()
                    await CloudKitSyncManager.shared.syncNow(silent: true)
                }
            }
            .onChange(of: appState.pendingCaregiverBeneficiaryToOpen) { _ in
                consumePendingBeneficiaryIfNeeded()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    medicationService.refreshDerivedState()
                    Task {
                        await CloudKitSyncManager.shared.syncNow(silent: true)
                    }
                }
            }
            .navigationDestination(for: BeneficiarySummary.self) { beneficiary in
                CaregiverPatientDetailView(beneficiary: beneficiary)
            }
            .preferredColorScheme(themeService.colorScheme)
        }
    }

    private func consumePendingBeneficiaryIfNeeded() {
        guard let beneficiary = appState.pendingCaregiverBeneficiaryToOpen else { return }
        showingCreateInvitationSheet = false
        showingReceiveInvitationSheet = false
        showingSettingsSheet = false
        showingReportSheet = false
        navigationPath = [beneficiary]
        appState.pendingCaregiverBeneficiaryToOpen = nil
    }

    // MARK: - 1. Top Header View
    @ViewBuilder
    private var headerView: some View {
        HStack(alignment: .center) {
            Text(identity.displayName)
                .dawaiFont(size: 34, weight: .bold, design: .rounded)
                .foregroundStyle(.primary)

            Spacer()

            // Reports Button (UC-7 S#1: Application navigation access for Caregivers)
            Button {
                showingReportSheet = true
            } label: {
                Image(systemName: "chart.bar.xaxis")
                    .dawaiFont(size: 18, weight: .semibold)
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
                    .dawaiFont(size: 18, weight: .semibold)
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
        HStack(spacing: 8) {
            Text("المستفيدين")
                .dawaiFont(size: 20, weight: .bold)
                .foregroundStyle(.primary)
                .textCase(nil)

            Spacer()

            Button {
                showingCreateInvitationSheet = true
            } label: {
                Image(systemName: "plus")
                    .dawaiFont(size: 15, weight: .bold)
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
            ForEach(medicationService.deletionRequests(forCaregiver: identity.id)) { req in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("طلب حذف: \(req.medicationName)")
                                .dawaiFont(size: 16, weight: .bold)
                                .foregroundStyle(.primary)
                            Text("من: \(req.patientDisplayName) • \(req.dosage)")
                                .dawaiFont(size: 13, weight: .medium)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "hourglass")
                                .dawaiFont(size: 10, weight: .bold)
                            Text("بانتظار موافقتك")
                                .dawaiFont(size: 11, weight: .bold)
                        }
                        .foregroundStyle(Color.dawaiWarning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.dawaiWarningBackground, in: Capsule())
                    }

                    HStack(spacing: 10) {
                        Button {
                            withAnimation {
                                medicationService.approveDeletionRequest(requestId: req.id, by: identity)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "trash.fill")
                                    .dawaiFont(size: 12, weight: .bold)
                                Text("قبول وحذف")
                                    .dawaiFont(size: 13, weight: .bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation {
                                medicationService.rejectDeletionRequest(requestId: req.id, by: identity)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.counterclockwise")
                                    .dawaiFont(size: 12, weight: .bold)
                                Text("رفض والاحتفاظ")
                                    .dawaiFont(size: 13, weight: .bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(rowBackground(hasDelayAlert: false))
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .foregroundStyle(Color.dawaiWarning)
                Text("طلبات حذف الأدوية من المستفيدين")
                    .dawaiFont(size: 15, weight: .bold)
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - 3. Beneficiaries Section (Native iOS System List)
    @ViewBuilder
    private var beneficiariesSection: some View {
        let activeRels = relationshipService.activeRelationships.filter { $0.caregiverId == identity.id && $0.isActive }
        let demoItems = demoMode.beneficiaries

        Section {
            if !activeRels.isEmpty {
                ForEach(activeRels, id: \.id) { rel in
                    activePatientRow(rel: rel)
                        .listRowBackground(rowBackground(hasDelayAlert: medicationService.daySchedule(forPatient: rel.patientId, at: medicationService.lastEvaluatedAt).hasMissedDoses))
                }
            } else if !demoItems.isEmpty {
                ForEach(demoItems, id: \.id) { item in
                    demoItemRow(item: item)
                }
            } else if !relationshipService.outgoingInvitations(for: identity).isEmpty || !relationshipService.incomingInvitations(for: identity).isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.badge.gearshape")
                            .dawaiFont(size: 26)
                            .foregroundStyle(Color.secondary)
                        Text("بانتظار اكتمال الارتباط")
                            .dawaiFont(size: 14, weight: .medium)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
                .listRowBackground(glassRowBackground)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "person.2.slash")
                        .dawaiFont(size: 32, weight: .regular)
                        .foregroundStyle(Color.dawaiPrimary.opacity(0.75))

                    Text("لا يوجد مستفيدون مرتبطون حالياً")
                        .dawaiFont(size: 16, weight: .bold)
                        .foregroundStyle(.primary)

                    Text("اضغط على زر (+) أعلى القائمة لإرسال دعوة ربط لمستفيد ومتابعة جدول أدويته.")
                        .dawaiFont(size: 13)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)

                    Button {
                        showingCreateInvitationSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "link.badge.plus")
                                .dawaiFont(size: 13, weight: .bold)
                            Text("إرسال دعوة ربط")
                                .dawaiFont(size: 13, weight: .bold)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.dawaiPrimary)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowBackground(glassRowBackground)
            }
        } header: {
            sectionHeaderView
        }
    }

    // MARK: - Demo Beneficiary Row
    @ViewBuilder
    private func demoItemRow(item: BeneficiarySummary) -> some View {
        NavigationLink(value: item) {
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
                .dawaiFont(size: 18)
                .foregroundStyle(Color.dawaiWarning)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .dawaiFont(size: 17, weight: .bold)
                    .foregroundStyle(.primary)

                if let notice = item.delayNotice {
                    Text(notice)
                        .dawaiFont(size: 13, weight: .medium)
                        .foregroundStyle(Color.dawaiWarning)
                }
            }

            Spacer()

            Text("متأخر")
                .dawaiFont(size: 11, weight: .bold)
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
                .dawaiFont(size: 17, weight: .semibold)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.vertical, 6)
    }

    // MARK: - Active Patient Row (Connected Glass Row)
    @ViewBuilder
    private func activePatientRow(rel: ActiveRelationship) -> some View {
        // Delay alerts come only from this linked patient's own medications.
        let schedule = medicationService.daySchedule(forPatient: rel.patientId, at: medicationService.lastEvaluatedAt)
        let hasDelay = schedule.hasMissedDoses
        let missedDose = schedule.missedDoses.first
        let missedMed = missedDose?.medication ?? schedule.missedMedications.first
        let delayNoticeText = missedMed != nil ? "30 د تأخير، \(missedMed!.name)" : nil
        let summary = BeneficiarySummary(
            id: rel.id,
            patientId: rel.patientId,
            name: rel.patientDisplayName,
            hasDelayAlert: hasDelay,
            delayNotice: delayNoticeText,
            scheduledTime: missedDose?.timeString ?? missedMed?.timeString,
            isInvitation: false,
            delayedMedicationName: missedMed?.name,
            delayedDosage: missedMed?.dosage,
            phoneNumber: "0501234567"
        )

        NavigationLink(value: summary) {
            if hasDelay {
                latePatientRow(item: summary)
            } else {
                HStack(spacing: 12) {
                    Text(rel.patientDisplayName)
                        .dawaiFont(size: 17, weight: .semibold)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("نشط")
                        .dawaiFont(size: 11, weight: .bold)
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
        let acceptedInvites = deduplicateInvitations(relationshipService.outgoingInvitations(for: identity, status: .accepted))
        let incomingInvites = deduplicateInvitations(relationshipService.incomingInvitations(for: identity))
        let pendingInvites = deduplicateInvitations(relationshipService.outgoingInvitations(for: identity, status: .pending))

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
                    .dawaiFont(size: 15, weight: .semibold)
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
                    .dawaiFont(size: 16, weight: .semibold)
                    .foregroundStyle(Color.dawaiTaken)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cleanDisplayName(invite.recipientDisplayName ?? "المستفيد"))
                    .dawaiFont(size: 16, weight: .semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("تم القبول • بانتظار التأكيد")
                    .dawaiFont(size: 13)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    handleConfirmConnection(invite: invite)
                } label: {
                    Text("تأكيد")
                        .dawaiFont(size: 13, weight: .bold)
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
                        .dawaiFont(size: 11, weight: .bold)
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
                    .dawaiFont(size: 16, weight: .semibold)
                    .foregroundStyle(Color.dawaiPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cleanDisplayName(incoming.initiatorDisplayName))
                    .dawaiFont(size: 16, weight: .semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("طلب ارتباط وارد")
                    .dawaiFont(size: 13)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    handleAcceptInvitation(incoming: incoming)
                } label: {
                    Text("قبول")
                        .dawaiFont(size: 13, weight: .bold)
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
                        .dawaiFont(size: 11, weight: .bold)
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
            Button {
                showingCreateInvitationSheet = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(uiColor: .systemGray5))
                            .frame(width: 36, height: 36)
                        Image(systemName: "link.badge.plus")
                            .dawaiFont(size: 16, weight: .medium)
                            .foregroundStyle(Color.dawaiPrimary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("دعوة مستفيد")
                            .dawaiFont(size: 16, weight: .semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text("بانتظار القبول")
                            .dawaiFont(size: 13)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Button {
                    UIPasteboard.general.string = invite.webInviteURL.absoluteString
                    relationshipService.notificationToastMessage = "تم نسخ رابط الدعوة بنجاح"
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .dawaiFont(size: 11, weight: .semibold)
                        Text("نسخ الرابط")
                            .dawaiFont(size: 12, weight: .semibold)
                    }
                    .foregroundStyle(Color.dawaiPrimary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.dawaiPrimary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("نسخ رابط الدعوة")

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        relationshipService.cancelOutgoingInvitation(invitationId: invite.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .dawaiFont(size: 11, weight: .bold)
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
                // e.g. the invitation expired before it was confirmed
                relationshipService.showToast(error.localizedDescription)
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
                relationshipService.showToast(error.localizedDescription)
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
                // Only a pending, unexpired invitation can be rejected
                relationshipService.showToast(error.localizedDescription)
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
