//
//  PatientHomeView.swift
//  Dawai
//
//  Patient Home View - Premium Apple Glass Mode Design
//  Decomposed into lightweight @ViewBuilder sub-expressions to ensure lightning-fast
//  Swift compiler type-checking without timeout errors.
//

import SwiftUI
import UIKit

public struct PatientHomeView: View {
    let identity: UserIdentity
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var relationshipService = RelationshipService.shared
    @ObservedObject private var medicationService = MedicationService.shared
    @ObservedObject private var adherenceService = AdherenceService.shared
    @ObservedObject private var themeService = ThemeService.shared

    // UC-2 Sheets State
    @State private var showingCreateInvitationSheet = false
    @State private var showingReceiveInvitationSheet = false
    @State private var showingSettingsSheet = false
    @State private var relationshipToUnlink: ActiveRelationship? = nil
    @State private var showingUnlinkAlert = false

    // UC-3 Add/Edit Medication State
    @State private var showingAddMedicationSheet = false
    @State private var editingMedication: MedicationItem? = nil

    // UC-4 & UC-6 Dose Confirmation State
    @State private var confirmingDose: ScheduledDose? = nil
    @State private var processingDoseId: String? = nil

    // UC-11 Delete Medication Confirmation State
    @State private var medicationToDelete: MedicationItem? = nil
    @State private var showingDeleteConfirmationAlert = false

    // UC-7 Adherence Report State
    @State private var showingReportSheet = false
    @State private var navigationPath: [BeneficiarySummary] = []

    public init(identity: UserIdentity) {
        self.identity = identity
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .top) {
                List {
                    // 1. Top Header Row
                    Section {
                        headerView
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    // 2. Hero Dose Counter Row
                    Section {
                        heroDoseCounterView
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    // 2.2 Overdue Dose Orange Alert Banner (when >= 30m late)
                    overdueAlertBannerSection

                    // 3. Active Medication or All Doses Completed
                    activeMedicationSection

                    // 4. Daily Schedule
                    upcomingDosesSection

                    // 5. Caregivers System List
                    caregiversSection
                }
                .listStyle(.insetGrouped)
                .compactListTopMargin()
                .scrollContentBackground(.hidden)
                .background(Color.dawaiBackground.ignoresSafeArea())
                .refreshable {
                    await CloudKitSyncManager.shared.syncNow(silent: false)
                }

                // Notification Toast (UC-2 S#8 & UC-3 S#8)
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
            .sheet(isPresented: $showingSettingsSheet) {
                IdentityDetailsSheet(identity: identity)
                    .preferredColorScheme(ThemeService.shared.colorScheme)
            }
            .sheet(isPresented: $showingReceiveInvitationSheet) {
                ReceiveInvitationSheet(currentUser: identity)
                    .preferredColorScheme(themeService.colorScheme)
            }
            .sheet(isPresented: $showingReportSheet) {
                AdherenceReportView(currentUser: identity)
                    .preferredColorScheme(ThemeService.shared.colorScheme)
            }
            .sheet(isPresented: $showingAddMedicationSheet) {
                MedicationFormView(mode: .add, currentUser: identity) {
                    showingAddMedicationSheet = false
                }
                .preferredColorScheme(ThemeService.shared.colorScheme)
            }
            .sheet(item: $editingMedication) { med in
                MedicationFormView(mode: .edit(med), currentUser: identity) {
                    editingMedication = nil
                }
                .preferredColorScheme(ThemeService.shared.colorScheme)
            }
            .sheet(item: $confirmingDose) { dose in
                DoseConfirmationSheet(
                    medication: dose.medication,
                    slotMinutes: dose.slotMinutes,
                    isCarryoverFromYesterday: dose.isCarryoverFromYesterday,
                    currentUser: identity,
                    onEditMedication: { med in
                        confirmingDose = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            editingMedication = med
                        }
                    }
                )
                .preferredColorScheme(ThemeService.shared.colorScheme)
            }
            .alert(
                !relationshipService.hasActiveCaregiver(forPatient: identity.id)
                    ? "تأكيد حذف دواء \"\(medicationToDelete?.name ?? "")\""
                    : "طلب حذف دواء \"\(medicationToDelete?.name ?? "")\"",
                isPresented: $showingDeleteConfirmationAlert
            ) {
                Button(
                    !relationshipService.hasActiveCaregiver(forPatient: identity.id) ? "حذف" : "إرسال طلب الحذف",
                    role: .destructive
                ) {
                    if let med = medicationToDelete {
                        if !relationshipService.hasActiveCaregiver(forPatient: identity.id) {
                            medicationService.deleteMedicationDirectly(id: med.id)
                        } else {
                            medicationService.requestMedicationDeletionByPatient(
                                medicationId: med.id,
                                patient: identity,
                                caregivers: relationshipService.activeRelationships
                            )
                        }
                    }
                    medicationToDelete = nil
                }
                Button("إلغاء", role: .cancel) {
                    medicationToDelete = nil
                }
            } message: {
                if !relationshipService.hasActiveCaregiver(forPatient: identity.id) {
                    Text("هل أنت متأكد من رغبتك في حذف هذا الدواء؟ سيتم إلغاء جميع التذكيرات وإزالته من جدولك نهائياً.")
                } else {
                    Text("هل أنت متأكد من رغبتك في حذف هذا الدواء؟ سيتم إرسال طلب الحذف لمقدم الرعاية المرتبط بك للموافقة على حذفه أو رفضه.")
                }
            }
            .confirmationDialog(
                "إنهاء الارتباط مع \(relationshipToUnlink?.caregiverDisplayName ?? "مقدم الرعاية")؟",
                isPresented: $showingUnlinkAlert,
                titleVisibility: .visible
            ) {
                Button("إنهاء الارتباط", role: .destructive) {
                    if let rel = relationshipToUnlink {
                        relationshipService.disconnect(relationshipId: rel.id)
                    }
                    relationshipToUnlink = nil
                }
                Button("إلغاء", role: .cancel) {
                    relationshipToUnlink = nil
                }
            } message: {
                let name = relationshipToUnlink?.caregiverDisplayName ?? "مقدم الرعاية"
                Text("لن يرى \(name) أدويتك وجرعاتك، ولن يصله تنبيه عند فوات جرعة.")
            }
            .onAppear {
                medicationService.refreshDerivedState()
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
        showingSettingsSheet = false
        showingReceiveInvitationSheet = false
        showingReportSheet = false
        showingAddMedicationSheet = false
        editingMedication = nil
        confirmingDose = nil
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

            // Reports Button (UC-7 S#1: Application navigation access)
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
            .accessibilityLabel("تقرير الالتزام الدوائي")

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

    // MARK: - 2. Daily Dose Progress Ring Glass Card
    @ViewBuilder
    private var heroDoseCounterView: some View {
        let remaining = medicationService.remainingDoses
        let todayCount = medicationService.todayMedications.count
        let totalCount = medicationService.medications.count
        let takenCount = max(0, todayCount - remaining)
        let progressFraction: CGFloat = todayCount > 0 ? CGFloat(takenCount) / CGFloat(todayCount) : 0.0

        HStack(spacing: 14) {
            // Apple Health / Fitness Style Progress Ring
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 4.5)
                    .frame(width: 44, height: 44)

                Circle()
                    .trim(from: 0.0, to: progressFraction)
                    .stroke(
                        (remaining == 0 && todayCount > 0) ? Color.dawaiTaken : Color.dawaiPrimary,
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75), value: progressFraction)

                if remaining == 0 && todayCount > 0 {
                    Image(systemName: "checkmark")
                        .dawaiFont(size: 15, weight: .bold)
                        .foregroundStyle(Color.dawaiTaken)
                } else if todayCount == 0 {
                    Image(systemName: "calendar")
                        .dawaiFont(size: 14, weight: .semibold)
                        .foregroundStyle(Color.dawaiPrimary)
                } else {
                    Text("\(Int(round(progressFraction * 100)))%")
                        .dawaiFont(size: 11, weight: .heavy, design: .rounded)
                        .foregroundStyle(.primary)
                }
            }

            // Status Texts
            VStack(alignment: .leading, spacing: 2) {
                Text("جرعات اليوم")
                    .dawaiFont(size: 12, weight: .semibold)
                    .foregroundStyle(.secondary)

                if totalCount == 0 {
                    Text("لا توجد أدوية مجدولة بعد")
                        .dawaiFont(size: 15, weight: .bold)
                        .foregroundStyle(.primary)
                } else if todayCount == 0 && totalCount > 0 {
                    Text("لا توجد جرعات مجدولة لليوم")
                        .dawaiFont(size: 15, weight: .bold)
                        .foregroundStyle(.primary)
                } else if remaining == 0 && todayCount > 0 {
                    Text("أكملت جميع جرعات اليوم 🎉")
                        .dawaiFont(size: 15, weight: .bold)
                        .foregroundStyle(Color.dawaiTaken)
                } else {
                    Text(doseCounterText(remaining: remaining))
                        .dawaiFont(size: 15, weight: .bold)
                        .foregroundStyle(.primary)
                }
            }

            Spacer()

            // Completion Fraction Badge
            if todayCount > 0 {
                HStack(spacing: 4) {
                    if remaining == 0 {
                        Image(systemName: "checkmark")
                            .dawaiFont(size: 11, weight: .bold)
                    }
                    Text("\(takenCount)/\(todayCount)")
                        .dawaiFont(size: 13, weight: .bold, design: .rounded)
                    Text("مكتملة")
                        .dawaiFont(size: 11, weight: .medium)
                }
                .foregroundStyle(remaining == 0 ? Color.dawaiTaken : Color.dawaiPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    (remaining == 0 ? Color.dawaiTaken : Color.dawaiPrimary).opacity(0.12),
                    in: Capsule()
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            Color(uiColor: UIColor { trait in
                                trait.userInterfaceStyle == .dark
                                    ? UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.75)
                                    : UIColor.white.withAlphaComponent(0.85)
                            })
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            Color(uiColor: UIColor { trait in
                                trait.userInterfaceStyle == .dark
                                    ? UIColor.clear
                                    : UIColor(Color.dawaiPrimary).withAlphaComponent(0.025)
                            })
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.dawaiGlassBorder, lineWidth: 1)
                )
        )
    }

    private func doseCounterText(remaining: Int) -> String {
        switch remaining {
        case 0:
            return "لا توجد جرعات متبقية اليوم"
        case 1:
            return "بقي جرعة واحدة"
        case 2:
            return "بقي جرعتان"
        default:
            return "بقي \(remaining) جرعات"
        }
    }

    // MARK: - 2.2 Overdue Dose Orange Alert Banner
    @ViewBuilder
    private var overdueAlertBannerSection: some View {
        let now = medicationService.lastEvaluatedAt
        let lateDoses = medicationService.todayDoses.filter { dose in
            medicationService.doseInteractionState(
                for: dose.medication,
                slotMinutes: dose.slotMinutes,
                at: now,
                isCarryover: dose.isCarryoverFromYesterday
            ) == .overdueLate
        }
        if let firstLate = lateDoses.first {
            Section {
                Button {
                    confirmingDose = firstLate
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.dawaiWarning)
                                .frame(width: 36, height: 36)

                            Image(systemName: "exclamationmark.triangle.fill")
                                .dawaiFont(size: 16, weight: .bold)
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(lateDoses.count == 1 ? "تأخر موعد دواء \(firstLate.medication.name)" : "لديك \(lateDoses.count) جرعات متأخرة")
                                .dawaiFont(size: 16, weight: .bold)
                                .foregroundStyle(.primary)

                            if lateDoses.count == 1 {
                                let mins = medicationService.overdueMinutes(
                                    for: firstLate.medication,
                                    slotMinutes: firstLate.slotMinutes,
                                    at: now,
                                    isCarryover: firstLate.isCarryoverFromYesterday
                                ) ?? DoseWindowConfig.lateThresholdMinutes
                                Text("متأخر بـ \(mins) دقيقة • الموعد: \(firstLate.timeString)")
                                    .dawaiFont(size: 13, weight: .semibold)
                                    .foregroundStyle(Color.dawaiWarning)
                            } else {
                                Text("\(lateDoses.map { "\($0.medication.name) (\($0.timeString))" }.joined(separator: "، ")) • اضغط للتأكيد")
                                    .dawaiFont(size: 13, weight: .semibold)
                                    .foregroundStyle(Color.dawaiWarning)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.left")
                            .dawaiFont(size: 13, weight: .bold)
                            .foregroundStyle(Color.dawaiWarning.opacity(0.85))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.dawaiWarningBackground.opacity(0.92))
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.dawaiWarning.opacity(0.10))
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.dawaiWarning.opacity(0.42), lineWidth: 1.4)
                    )
                }
                .buttonStyle(.plain)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: - 2.5 Adherence Quick Banner (UC-7)
    @ViewBuilder
    private var adherenceQuickBanner: some View {
        let periods = AdherenceService.shared.availableWeekPeriods(count: 1)
        if let currentPeriod = periods.first {
            let report = AdherenceService.shared.generateWeeklyReport(
                patientId: identity.id,
                patientDisplayName: identity.displayName,
                period: currentPeriod
            )
            if report.hasSufficientData {
                Button {
                    showingReportSheet = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 4)
                                .frame(width: 40, height: 40)
                            Circle()
                                .trim(from: 0.0, to: min(1.0, CGFloat(report.adherencePercentage / 100.0)))
                                .stroke(report.tier.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 40, height: 40)
                            Text("\(Int(round(report.adherencePercentage)))%")
                                .dawaiFont(size: 11, weight: .heavy, design: .rounded)
                                .foregroundStyle(.primary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("الالتزام الأسبوعي")
                                    .dawaiFont(size: 14, weight: .bold)
                                    .foregroundStyle(.primary)
                                Text(report.tier.titleArabic)
                                    .dawaiFont(size: 11, weight: .bold)
                                    .foregroundStyle(report.tier.color)
                            }
                            Text("تم تناول \(report.totalTaken) من \(report.totalScheduled) جرعة • اضغط لعرض التقرير الكامل")
                                .dawaiFont(size: 11)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.left")
                            .dawaiFont(size: 12, weight: .semibold)
                            .foregroundStyle(Color.dawaiPrimary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.dawaiGlassBorder, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 3. Active Medication Section (UC-12: Auto-Sorted Daily Schedule)
    @ViewBuilder
    private var activeMedicationSection: some View {
        Section {
            if medicationService.todayDoses.isEmpty && !medicationService.medications.isEmpty {
                // UC-12 Alternate Course S#1: No medications scheduled for the current day
                noMedicationsTodayCard
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if medicationService.remainingDoses == 0 && !medicationService.todayDoses.isEmpty {
                // When all doses for today are taken or missed: display today's doses in native iOS list rows
                allDosesCompletedRows
            } else if !medicationService.activeDoses.isEmpty {
                ForEach(medicationService.activeDoses) { dose in
                    let isLast = (dose.id == medicationService.activeDoses.last?.id)
                    activeDoseCard(dose)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: isLast ? 0 : 12, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        // Swipe Actions (Delete & Edit on the same edge, exactly like iOS Mail/Reminders)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                medicationToDelete = dose.medication
                                showingDeleteConfirmationAlert = true
                            } label: {
                                Label("حذف", systemImage: "trash")
                            }

                            Button {
                                editingMedication = dose.medication
                            } label: {
                                Label("تعديل", systemImage: "pencil")
                            }
                            .tint(Color.dawaiPrimary)
                        }
                }
            } else {
                emptyMedicationsCard
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        } header: {
            medicationsSectionHeader
        }
    }

    @ViewBuilder
    private var medicationsSectionHeader: some View {
        HStack {
            Text("ادويتي")
                .dawaiFont(size: 20, weight: .bold)
                .foregroundStyle(.primary)
                .textCase(nil)

            Spacer()

            Button {
                showingAddMedicationSheet = true
            } label: {
                Image(systemName: "plus")
                    .dawaiFont(size: 15, weight: .bold)
                    .foregroundStyle(Color.dawaiPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.dawaiPrimary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("إضافة دواء جديد")
        }
    }

    // MARK: - All Doses Completed State (Native iOS List Rows)
    @ViewBuilder
    private var allDosesCompletedRows: some View {
        ForEach(medicationService.todayDoses) { dose in
            let med = dose.medication
            let state = medicationService.doseInteractionState(
                for: med,
                slotMinutes: dose.slotMinutes,
                at: medicationService.lastEvaluatedAt,
                isCarryover: dose.isCarryoverFromYesterday
            )
            let isTakenToday = (state == .taken)
            HStack(spacing: 12) {
                Button {
                    confirmingDose = dose
                } label: {
                    HStack(spacing: 12) {
                        medicationRowThumbnail(imageData: med.imageData, isTaken: isTakenToday)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(med.name)
                                .dawaiFont(size: 16, weight: .semibold)
                                .foregroundStyle(.primary)

                            Text("\(med.dosage) • \(dose.timeString)")
                                .dawaiFont(size: 13, weight: .medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if med.isPendingDeletion {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                            .dawaiFont(size: 10, weight: .bold)
                        Text("بانتظار الموافقة")
                            .dawaiFont(size: 11, weight: .bold)
                    }
                    .foregroundStyle(Color.dawaiWarning)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.dawaiWarningBackground, in: Capsule())
                } else if state == .missed {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .dawaiFont(size: 10, weight: .bold)
                        Text("فائتة")
                            .dawaiFont(size: 11, weight: .bold)
                    }
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.10), in: Capsule())
                } else {
                    Text("تم أخذها")
                        .dawaiFont(size: 11, weight: .bold)
                        .foregroundStyle(Color.dawaiTaken)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.dawaiTakenBadgeBackground, in: Capsule())
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(glassRowBackground)
            // Swipe Actions (Delete & Edit on trailing edge)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if !med.isPendingDeletion {
                    Button(role: .destructive) {
                        medicationToDelete = med
                        showingDeleteConfirmationAlert = true
                    } label: {
                        Label("حذف", systemImage: "trash")
                    }
                }

                Button {
                    editingMedication = med
                } label: {
                    Label("تعديل", systemImage: "pencil")
                }
                .tint(Color.dawaiPrimary)
            }
        }
    }

    // MARK: - Active Dose Card (Per-Slot Support)
    @ViewBuilder
    private func activeDoseCard(_ dose: ScheduledDose) -> some View {
        let activeMedication = dose.medication
        let now = medicationService.lastEvaluatedAt
        let interactionState = medicationService.doseInteractionState(
            for: activeMedication,
            slotMinutes: dose.slotMinutes,
            at: now,
            isCarryover: dose.isCarryoverFromYesterday
        )
        let isTakenSlot = (interactionState == .taken)
        let isConfirmingThisDose = (processingDoseId == dose.id)

        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Button {
                    confirmingDose = dose
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        // Medication Image or Pill Icon Frame on RIGHT (FIRST in HStack)
                        medicationHeroThumbnail(imageData: activeMedication.imageData, isTaken: isTakenSlot)

                        // Details in CENTER
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activeMedication.name)
                                .dawaiFont(size: 22, weight: .bold)
                                .foregroundStyle(.primary)

                            Text(activeMedication.dosage)
                                .dawaiFont(size: 15, weight: .medium)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 6) {
                                Text(dose.timeString)
                                    .dawaiFont(size: 14, weight: .semibold)
                                    .foregroundStyle(
                                        isTakenSlot
                                            ? Color.dawaiTaken
                                            : (interactionState == .overdueLate
                                                ? Color.dawaiWarning
                                                : (interactionState == .missed ? Color.red : Color.dawaiPrimary))
                                    )

                                if activeMedication.isPendingDeletion {
                                    Text("• بانتظار موافقة الحذف")
                                        .dawaiFont(size: 12, weight: .bold)
                                        .foregroundStyle(Color.dawaiWarning)
                                } else if isTakenSlot {
                                    Text("• تم أخذها")
                                        .dawaiFont(size: 13, weight: .bold)
                                        .foregroundStyle(Color.dawaiTaken)
                                } else if interactionState == .overdueLate {
                                    let mins = medicationService.overdueMinutes(
                                        for: activeMedication,
                                        slotMinutes: dose.slotMinutes,
                                        at: now,
                                        isCarryover: dose.isCarryoverFromYesterday
                                    ) ?? DoseWindowConfig.lateThresholdMinutes
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .dawaiFont(size: 10, weight: .bold)
                                        Text("متأخرة منذ \(mins) د")
                                            .dawaiFont(size: 12, weight: .bold)
                                    }
                                    .foregroundStyle(Color.dawaiWarning)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.dawaiWarningBadgeBackground, in: Capsule())
                                    .overlay(
                                        Capsule().stroke(Color.dawaiWarningBorder, lineWidth: 0.8)
                                    )
                                } else if interactionState == .missed {
                                    Text("• جرعة فائتة")
                                        .dawaiFont(size: 13, weight: .bold)
                                        .foregroundStyle(Color.red)
                                }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, isTakenSlot ? 16 : 0)

            // Dose Confirmation or Window Status Banner (UC-4 & UC-6)
            switch interactionState {
            case .taken:
                EmptyView()

            case .upcomingBeforeWindow, .dueOnTime, .overdueLate:
                let isDue = (interactionState == .dueOnTime || interactionState == .overdueLate)
                Button {
                    guard isDue, !isConfirmingThisDose, !isTakenSlot else { return }
                    processingDoseId = dose.id
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        _ = medicationService.confirmDoseTaken(
                            id: activeMedication.id,
                            slotMinutes: dose.slotMinutes,
                            patient: identity
                        )
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        if processingDoseId == dose.id {
                            processingDoseId = nil
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isConfirmingThisDose {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .dawaiFont(size: 18, weight: .bold)
                            Text("تأكيد أخذ الدواء")
                                .dawaiFont(size: 17, weight: .bold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        isDue
                            ? LinearGradient(
                                colors: interactionState == .overdueLate
                                    ? [Color.dawaiWarning, Color.dawaiWarning.opacity(0.92)]
                                    : [Color.dawaiPrimary, Color(red: 0/255, green: 110/255, blue: 107/255)],
                                startPoint: .top,
                                endPoint: .bottom
                              )
                            : LinearGradient(
                                colors: [Color(uiColor: .systemGray5), Color(uiColor: .systemGray5)],
                                startPoint: .top,
                                endPoint: .bottom
                              )
                    )
                    .foregroundStyle(isDue ? Color.white : Color(uiColor: .secondaryLabel).opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                isDue ? Color.white.opacity(0.25) : Color.black.opacity(0.05),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(ActionBounceButtonStyle())
                .disabled(!isDue || isConfirmingThisDose || isTakenSlot)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

            case .missed:
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .dawaiFont(size: 16, weight: .semibold)
                    Text("جرعة فائتة • انتهى وقت التأكيد")
                        .dawaiFont(size: 15, weight: .bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.red.opacity(0.10))
                .foregroundStyle(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                if isTakenSlot {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.dawaiTakenBackground)
                } else if interactionState == .overdueLate {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.dawaiWarningBackground.opacity(0.92))
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.dawaiWarning.opacity(0.08))
                } else {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.dawaiGlassFill)
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.dawaiGlassTint)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    isTakenSlot
                        ? Color.dawaiTakenBorder
                        : (interactionState == .overdueLate ? Color.dawaiWarning.opacity(0.45) : Color.dawaiGlassBorder),
                    lineWidth: (isTakenSlot || interactionState == .overdueLate) ? 1.5 : 1
                )
        )
    }

    // MARK: - Medication Image Thumbnail Helpers
    @ViewBuilder
    private func medicationHeroThumbnail(imageData: Data?, isTaken: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isTaken ? Color.dawaiTaken : Color.dawaiGlassBorder, lineWidth: isTaken ? 2 : 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isTaken ? Color.dawaiTakenBadgeBackground : Color.dawaiPrimary.opacity(0.12))
                        .frame(width: 68, height: 68)

                    Image(systemName: isTaken ? "checkmark.circle.fill" : "pill.fill")
                        .dawaiFont(size: 32)
                        .foregroundStyle(isTaken ? Color.dawaiTaken : Color.dawaiPrimary)
                        .rotationEffect(isTaken ? .degrees(0) : .degrees(-45))
                }
            }

            if isTaken && imageData != nil {
                Image(systemName: "checkmark.circle.fill")
                    .dawaiFont(size: 18, weight: .bold)
                    .foregroundStyle(.white, Color.dawaiTaken)
                    .offset(x: -4, y: 4)
            }
        }
    }

    @ViewBuilder
    private func medicationRowThumbnail(imageData: Data?, isTaken: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isTaken ? Color.dawaiTaken : Color.dawaiGlassBorder, lineWidth: 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isTaken ? Color.dawaiTakenBadgeBackground : Color.dawaiPrimary.opacity(0.10))
                        .frame(width: 42, height: 42)

                    Image(systemName: isTaken ? "checkmark.circle.fill" : "pill.fill")
                        .dawaiFont(size: 18, weight: .semibold)
                        .foregroundStyle(isTaken ? Color.dawaiTaken : Color.dawaiPrimary)
                        .rotationEffect(isTaken ? .degrees(0) : .degrees(-45))
                }
            }

            if isTaken && imageData != nil {
                Image(systemName: "checkmark.circle.fill")
                    .dawaiFont(size: 14, weight: .bold)
                    .foregroundStyle(.white, Color.dawaiTaken)
                    .offset(x: -3, y: 3)
            }
        }
    }

    // MARK: - Empty Medications Fallback Card
    @ViewBuilder
    private var emptyMedicationsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "pill.fill")
                .dawaiFont(size: 32)
                .foregroundStyle(Color.dawaiPrimary)

            Text("لا توجد أدوية مجدولة")
                .dawaiFont(size: 17, weight: .bold)
                .foregroundStyle(.primary)

            Text("اضغط على (+) في الأعلى لإضافة دواء وتحديد مواعيد الجرعات.")
                .dawaiFont(size: 14)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.dawaiGlassFill)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.dawaiGlassTint)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
        )
    }

    // MARK: - UC-12 Alternate Course S#1: No Medications Scheduled for Today
    @ViewBuilder
    private var noMedicationsTodayCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .dawaiFont(size: 32)
                .foregroundStyle(Color.dawaiPrimary)

            Text("لا توجد أدوية مجدولة لليوم")
                .dawaiFont(size: 17, weight: .bold)
                .foregroundStyle(.primary)

            Text("جميع أدويتك المسجلة مجدولة في أيام أخرى. اضغط على (+) لإضافة دواء جديد أو لتعديل المواعيد.")
                .dawaiFont(size: 14)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.dawaiGlassFill)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.dawaiGlassTint)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
        )
    }

    // MARK: - 4. Daily Schedule Section (Formerly "باقي اليوم" -> "جدول اليوم")
    @ViewBuilder
    private var upcomingDosesSection: some View {
        // When all doses of the day are taken (remainingDoses == 0), the schedule collapses into "أدويتي" at the top
        if medicationService.remainingDoses > 0 && !medicationService.upcomingDoses.isEmpty {
            Section {
                ForEach(medicationService.upcomingDoses.indices, id: \.self) { index in
                    let dose = medicationService.upcomingDoses[index]
                    let fullMed = medicationService.medications.first(where: { $0.id == dose.medicationId })
                    let resolvedSlot = dose.slotMinutes ?? fullMed.map { medicationService.scheduledMinutes(for: $0) }
                    let matchingScheduledDose = medicationService.todayDoses.first {
                        $0.medication.id == dose.medicationId && $0.slotMinutes == resolvedSlot
                    }
                    let doseState = fullMed.map { med in
                        medicationService.doseInteractionState(
                            for: med,
                            slotMinutes: resolvedSlot ?? medicationService.scheduledMinutes(for: med),
                            at: medicationService.lastEvaluatedAt,
                            isCarryover: matchingScheduledDose?.isCarryoverFromYesterday ?? false
                        )
                    }
                    HStack(spacing: 12) {
                        Button {
                            let targetMed = fullMed ?? MedicationItem(
                                id: dose.medicationId,
                                patientId: identity.id,
                                name: dose.name,
                                dosage: dose.dosage,
                                timeString: dose.timeString,
                                imageData: dose.imageData,
                                isTaken: dose.isTaken
                            )
                            let targetSlot = resolvedSlot ?? medicationService.scheduledMinutes(for: targetMed)
                            confirmingDose = matchingScheduledDose ?? ScheduledDose(
                                medication: targetMed,
                                slotMinutes: targetSlot,
                                occurrenceDate: medicationService.scheduledDateTime(for: targetMed, on: medicationService.lastEvaluatedAt, slotMinutes: targetSlot),
                                timeString: dose.timeString
                            )
                        } label: {
                            HStack(spacing: 12) {
                                medicationRowThumbnail(imageData: dose.imageData ?? fullMed?.imageData, isTaken: dose.isTaken)

                                // Medication Name & Dosage on RIGHT (Leading in RTL)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dose.name)
                                        .dawaiFont(size: 16, weight: .bold)
                                        .foregroundStyle(dose.isTaken ? .secondary : .primary)

                                    Text(dose.dosage)
                                        .dawaiFont(size: 13, weight: .medium)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // Status / Time in CENTER
                        if dose.isTaken {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .dawaiFont(size: 13, weight: .bold)
                                Text("تم أخذها")
                                    .dawaiFont(size: 12, weight: .bold)
                            }
                            .foregroundStyle(Color.dawaiTaken)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.dawaiTakenBadgeBackground, in: Capsule())
                        } else if doseState == .overdueLate {
                            HStack(spacing: 5) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .dawaiFont(size: 11, weight: .bold)
                                Text("متأخرة • \(dose.timeString)")
                                    .dawaiFont(size: 12, weight: .bold)
                            }
                            .foregroundStyle(Color.dawaiWarning)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.dawaiWarningBadgeBackground, in: Capsule())
                            .overlay(
                                Capsule().stroke(Color.dawaiWarningBorder, lineWidth: 0.8)
                            )
                        } else if doseState == .missed {
                            HStack(spacing: 5) {
                                Image(systemName: "xmark.circle.fill")
                                    .dawaiFont(size: 11, weight: .bold)
                                Text("فائتة")
                                    .dawaiFont(size: 12, weight: .bold)
                            }
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.10), in: Capsule())
                        } else {
                            HStack(spacing: 5) {
                                Image(systemName: "clock")
                                    .dawaiFont(size: 12, weight: .semibold)
                                Text(dose.timeString)
                                    .dawaiFont(size: 13, weight: .semibold)
                            }
                            .foregroundStyle(Color.primary.opacity(0.75))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(scheduleRowBackground(isLate: doseState == .overdueLate))
                    // Swipe Actions (Delete & Edit on trailing edge)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            if let med = medicationService.medications.first(where: { $0.id == dose.medicationId }) {
                                medicationToDelete = med
                                showingDeleteConfirmationAlert = true
                            }
                        } label: {
                            Label("حذف", systemImage: "trash")
                        }

                        Button {
                            if let med = medicationService.medications.first(where: { $0.id == dose.medicationId }) {
                                editingMedication = med
                            }
                        } label: {
                            Label("تعديل", systemImage: "pencil")
                        }
                        .tint(Color.dawaiPrimary)
                    }
                }
            } header: {
                Text("جدول اليوم")
                    .dawaiFont(size: 20, weight: .bold)
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
        }
    }

    // MARK: - Glass Row Background Helper
    @ViewBuilder
    private func scheduleRowBackground(isLate: Bool) -> some View {
        if isLate {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.dawaiWarningBackground.opacity(0.92))
                .overlay(Color.dawaiWarning.opacity(0.08))
        } else {
            glassRowBackground
        }
    }

    private var glassRowBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(
                Color(uiColor: UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.75)
                        : UIColor.white.withAlphaComponent(0.85)
                })
            )
            .overlay(
                Color(uiColor: UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor.clear
                        : UIColor(Color.dawaiPrimary).withAlphaComponent(0.025)
                })
            )
    }

    // MARK: - 5. Caregivers Section (Up to 3 Caregivers per Patient)
    @ViewBuilder
    private var caregiversSection: some View {
        let activeRels = relationshipService.activeCaregivers(forPatient: identity.id)
        let accepted = deduplicateInvitations(relationshipService.outgoingInvitations(for: identity, status: .accepted))
        let incoming = deduplicateInvitations(relationshipService.incomingInvitations(for: identity))
        let pending = deduplicateInvitations(relationshipService.outgoingInvitations(for: identity, status: .pending))
        let isEmpty = activeRels.isEmpty && accepted.isEmpty && incoming.isEmpty && pending.isEmpty

        Section {
            if !activeRels.isEmpty {
                ForEach(activeRels) { rel in
                    activeCaregiverCard(rel: rel)
                        .listRowBackground(glassRowBackground)
                }

                ForEach(accepted) { invite in
                    acceptedCaregiverCard(invite: invite)
                        .listRowBackground(glassRowBackground)
                }

                ForEach(incoming) { inc in
                    incomingCaregiverCard(incoming: inc)
                        .listRowBackground(glassRowBackground)
                }

                ForEach(pending) { invite in
                    pendingCaregiverCard(invite: invite)
                        .listRowBackground(glassRowBackground)
                }
            } else if isEmpty {
                fallbackCaregiverCard
                    .listRowBackground(glassRowBackground)
            } else {
                ForEach(accepted) { invite in
                    acceptedCaregiverCard(invite: invite)
                        .listRowBackground(glassRowBackground)
                }

                ForEach(incoming) { inc in
                    incomingCaregiverCard(incoming: inc)
                        .listRowBackground(glassRowBackground)
                }

                ForEach(pending) { invite in
                    pendingCaregiverCard(invite: invite)
                        .listRowBackground(glassRowBackground)
                }
            }
        } header: {
            caregiversSectionHeader
        }
    }

    private func deduplicateInvitations(_ list: [ConnectionInvitation]) -> [ConnectionInvitation] {
        var seen = Set<String>()
        return list.filter { inv in
            let key = inv.token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return seen.insert(key).inserted
        }
    }

    @ViewBuilder
    private var caregiversSectionHeader: some View {
        let hasReachedLimit = relationshipService.hasReachedCaregiverLimit(forPatient: identity.id)
        HStack(spacing: 8) {
            Text("مقدمو الرعاية")
                .dawaiFont(size: 20, weight: .bold)
                .foregroundStyle(.primary)
                .textCase(nil)

            Spacer()

            if !hasReachedLimit {
                Button {
                    showingCreateInvitationSheet = true
                } label: {
                    Image(systemName: "plus")
                        .dawaiFont(size: 15, weight: .bold)
                        .foregroundStyle(Color.dawaiPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color.dawaiPrimary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("إنشاء دعوة مقدم رعاية")
            }
        }
    }

    // MARK: - Caregiver Cards Helpers (Native iOS System List Rows)
    @ViewBuilder
    private func acceptedCaregiverCard(invite: ConnectionInvitation) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.dawaiTaken.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "link.badge.plus")
                    .dawaiFont(size: 16, weight: .semibold)
                    .foregroundStyle(Color.dawaiTaken)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cleanDisplayName(invite.recipientDisplayName ?? "مقدم رعاية"))
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
    private func activeCaregiverCard(rel: ActiveRelationship) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.dawaiPrimary.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "person.fill")
                    .dawaiFont(size: 17, weight: .semibold)
                    .foregroundStyle(Color.dawaiPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cleanDisplayName(rel.caregiverDisplayName))
                    .dawaiFont(size: 16, weight: .semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Text("نشط")
                    .dawaiFont(size: 11, weight: .bold)
                    .foregroundStyle(Color.dawaiTaken)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.dawaiTakenBadgeBackground, in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                relationshipToUnlink = rel
                showingUnlinkAlert = true
            } label: {
                Label("إنهاء الارتباط", systemImage: "person.crop.circle.badge.xmark")
            }
        }
    }

    @ViewBuilder
    private func incomingCaregiverCard(incoming: ConnectionInvitation) -> some View {
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
    private func pendingCaregiverCard(invite: ConnectionInvitation) -> some View {
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
                        Text("دعوة مقدم رعاية")
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
                    medicationService.showToast("تم نسخ رابط الدعوة بنجاح")
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

    @ViewBuilder
    private var fallbackCaregiverCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("لا يوجد مقدم رعاية مرتبط")
                    .dawaiFont(size: 16, weight: .semibold)
                    .foregroundStyle(.primary)

                Text("اربط مقدم رعاية واحد لمتابعة وإدارة أدويتك")
                    .dawaiFont(size: 13)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showingCreateInvitationSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .dawaiFont(size: 11, weight: .bold)
                    Text("دعوة")
                        .dawaiFont(size: 12, weight: .semibold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.dawaiPrimary.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.dawaiPrimary)
                .fixedSize()
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
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

// MARK: - Use-Case 4 (UC-4) Step 5 & Use-Case 6 (UC-6) Step 6: Dose Confirmation Sheet
public struct DoseConfirmationSheet: View {
    public let medication: MedicationItem
    public let slotMinutes: Int?
    public let isCarryoverFromYesterday: Bool
    public let currentUser: UserIdentity
    public var onConfirmed: (() -> Void)? = nil
    public var onDismiss: (() -> Void)? = nil
    public var onEditMedication: ((MedicationItem) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var medicationService = MedicationService.shared
    @ObservedObject private var themeService = ThemeService.shared

    @State private var hasConfirmed: Bool = false
    @State private var isProcessing: Bool = false

    private var liveMedication: MedicationItem {
        medicationService.allMedications.first(where: { $0.id == medication.id }) ?? medication
    }

    private var effectiveSlotMinutes: Int {
        slotMinutes ?? medicationService.scheduledMinutes(for: liveMedication)
    }

    private var slotTimeString: String {
        medicationService.formattedTimeString(forSlotMinutes: effectiveSlotMinutes)
    }

    private var interactionState: MedicationService.DoseInteractionState {
        medicationService.doseInteractionState(
            for: liveMedication,
            slotMinutes: effectiveSlotMinutes,
            at: medicationService.lastEvaluatedAt,
            isCarryover: isCarryoverFromYesterday
        )
    }

    private var isAlreadyTaken: Bool {
        hasConfirmed || interactionState == .taken
    }

    private var isDoseMissedInReport: Bool {
        interactionState == .missed
    }

    public init(
        medication: MedicationItem,
        slotMinutes: Int? = nil,
        isCarryoverFromYesterday: Bool = false,
        currentUser: UserIdentity,
        onConfirmed: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        onEditMedication: ((MedicationItem) -> Void)? = nil
    ) {
        self.medication = medication
        self.slotMinutes = slotMinutes
        self.isCarryoverFromYesterday = isCarryoverFromYesterday
        self.currentUser = currentUser
        self.onConfirmed = onConfirmed
        self.onDismiss = onDismiss
        self.onEditMedication = onEditMedication
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - 1. Hero Medication Illustration / Image
                    heroImageView
                        .padding(.top, 16)

                    // MARK: - 2. Title & Status Badge
                    VStack(spacing: 8) {
                        if isAlreadyTaken {
                            Label("تم تأكيد الجرعة بنجاح", systemImage: "checkmark.circle.fill")
                                .dawaiFont(size: 14, weight: .bold)
                                .foregroundStyle(Color.dawaiTaken)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.dawaiTakenBadgeBackground, in: Capsule())
                        } else if isDoseMissedInReport {
                            Label("جرعة فائتة • انتهى وقت التأكيد", systemImage: "xmark.circle.fill")
                                .dawaiFont(size: 14, weight: .bold)
                                .foregroundStyle(Color.red)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.12), in: Capsule())
                        } else if interactionState == .overdueLate {
                            Label("جرعة متأخرة", systemImage: "exclamationmark.triangle.fill")
                                .dawaiFont(size: 14, weight: .bold)
                                .foregroundStyle(Color.dawaiWarning)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.dawaiWarningBadgeBackground, in: Capsule())
                        } else if interactionState == .dueOnTime {
                            Label("حان موعد الجرعة الآن", systemImage: "bell.badge.fill")
                                .dawaiFont(size: 14, weight: .bold)
                                .foregroundStyle(Color.dawaiWarning)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.dawaiWarningBadgeBackground, in: Capsule())
                        } else {
                            Label("جرعة مجدولة • \(slotTimeString)", systemImage: "clock.fill")
                                .dawaiFont(size: 14, weight: .bold)
                                .foregroundStyle(Color.dawaiPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.dawaiPrimary.opacity(0.12), in: Capsule())
                        }

                        Text(liveMedication.name)
                            .dawaiFont(size: 32, weight: .bold, design: .rounded)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 10) {
                            // Dosage Pill
                            HStack(spacing: 5) {
                                Image(systemName: "pills.fill")
                                    .dawaiFont(size: 13)
                                Text(liveMedication.dosage.westernNumerals)
                                    .dawaiFont(size: 15, weight: .semibold)
                            }
                            .foregroundStyle(Color.dawaiPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.dawaiPrimary.opacity(0.12), in: Capsule())

                            // Time Pill
                            HStack(spacing: 5) {
                                Image(systemName: "clock.fill")
                                    .dawaiFont(size: 13)
                                Text(slotTimeString)
                                    .dawaiFont(size: 15, weight: .semibold)
                            }
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
                        }
                        .padding(.top, 4)
                    }

                    // MARK: - 3. Medication Schedule & Instructions Card
                    medicationDetailsCard

                    // MARK: - 4. Prominent Action Buttons (S#5 & S#6)
                    actionButtonsSection
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color.dawaiBackground.ignoresSafeArea())
            .preferredColorScheme(themeService.colorScheme)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale.dawaiArabic)
            .navigationTitle("تأكيد الجرعة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("إغلاق") {
                        dismiss()
                        onDismiss?()
                    }
                    .dawaiFont(size: 16, weight: .semibold)
                    .foregroundStyle(Color.dawaiPrimary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let med = liveMedication
                        dismiss()
                        onDismiss?()
                        onEditMedication?(med)
                    } label: {
                        Image(systemName: "pencil")
                            .dawaiFont(size: 16, weight: .bold)
                            .foregroundStyle(Color.dawaiPrimary)
                    }
                    .accessibilityLabel("تعديل الدواء")
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale.dawaiArabic)
    }

    // MARK: - 1. Hero Image / Icon View
    @ViewBuilder
    private var heroImageView: some View {
        if let imageData = liveMedication.imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.dawaiGlassBorder, lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        } else {
            ZStack {
                Circle()
                    .fill(isAlreadyTaken ? Color.dawaiTakenBadgeBackground : Color.dawaiPrimary.opacity(0.12))
                    .frame(width: 110, height: 110)

                Image(systemName: isAlreadyTaken ? "checkmark.circle.fill" : "pills.circle.fill")
                    .dawaiFont(size: 58)
                    .foregroundStyle(isAlreadyTaken ? Color.dawaiTaken : Color.dawaiPrimary)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - 3. Medication Details Card
    @ViewBuilder
    private var medicationDetailsCard: some View {
        VStack(spacing: 14) {
            // Days & Frequency
            HStack {
                Label("التكرار والجدول", systemImage: "calendar")
                    .dawaiFont(size: 15, weight: .medium)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(liveMedication.frequency) • \(liveMedication.days.joined(separator: "، "))")
                    .dawaiFont(size: 15, weight: .semibold)
                    .foregroundStyle(.primary)
            }

            Divider()

            // Instructions (if present)
            if let instructions = liveMedication.instructions, !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("تعليمات الاستخدام", systemImage: "info.circle.fill")
                        .dawaiFont(size: 14, weight: .bold)
                        .foregroundStyle(Color.dawaiPrimary)

                    Text(instructions)
                        .dawaiFont(size: 15, weight: .medium)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color.dawaiPrimary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Duration
            HStack {
                Label("مدة العلاج", systemImage: "hourglass")
                    .dawaiFont(size: 15, weight: .medium)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(liveMedication.duration)
                    .dawaiFont(size: 15, weight: .semibold)
                    .foregroundStyle(.primary)
            }
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.dawaiGlassFill)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.dawaiGlassTint)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
        )
    }

    // MARK: - 4. Prominent Action Buttons (S#5 & S#6)
    @ViewBuilder
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            if isAlreadyTaken {
                // Already confirmed state
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .dawaiFont(size: 22)
                    Text("تم تأكيد أخذ الجرعة")
                        .dawaiFont(size: 18, weight: .bold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.dawaiTaken)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if isDoseMissedInReport {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.circle.fill")
                        .dawaiFont(size: 22)
                    Text("جرعة فائتة • انتهى وقت التأكيد")
                        .dawaiFont(size: 18, weight: .bold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                let isDue = (interactionState == .dueOnTime || interactionState == .overdueLate)

                // Prominent "I Took It" Button (UC-4 S#5 & S#6)
                Button {
                    guard isDue else { return }
                    confirmDose()
                } label: {
                    HStack(spacing: 10) {
                        if isProcessing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .dawaiFont(size: 22, weight: .bold)
                            Text("تأكيد أخذ الجرعة")
                                .dawaiFont(size: 19, weight: .bold)
                        }
                    }
                    .foregroundStyle(isDue ? Color.white : Color(uiColor: .secondaryLabel).opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        isDue
                            ? (interactionState == .overdueLate ? Color.dawaiWarning : Color.dawaiPrimary)
                            : Color(uiColor: .systemGray5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(ActionBounceButtonStyle())
                .disabled(!isDue || isProcessing || isAlreadyTaken)

                // Secondary dismiss / "Remind me later" Button
                Button {
                    dismiss()
                    onDismiss?()
                } label: {
                    Text(isDue ? "سآخذها لاحقاً" : "إغلاق")
                        .dawaiFont(size: 16, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Action: Confirm Dose Taken (UC-6)
    private func confirmDose() {
        guard !isProcessing, !isAlreadyTaken, !isDoseMissedInReport else { return }
        isProcessing = true
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            let didConfirm = medicationService.confirmDoseTaken(
                id: medication.id,
                slotMinutes: effectiveSlotMinutes,
                patient: currentUser
            )
            hasConfirmed = didConfirm || (interactionState == .taken)
            isProcessing = false
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onConfirmed?()

        // Smooth auto-dismiss after confirming
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            dismiss()
        }
    }
}

// MARK: - Interactive Button Style with Visual Press Affordance
private struct ActionBounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
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
