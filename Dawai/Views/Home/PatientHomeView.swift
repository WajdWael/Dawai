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
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var relationshipService = RelationshipService.shared
    @ObservedObject private var medicationService = MedicationService.shared
    @ObservedObject private var themeService = ThemeService.shared

    // UC-2 Sheets State
    @State private var showingCreateInvitationSheet = false
    @State private var showingSettingsSheet = false

    // UC-3 Add/Edit Medication State
    @State private var showingAddMedicationSheet = false
    @State private var editingMedication: MedicationItem? = nil

    // UC-4 & UC-6 Dose Confirmation State
    @State private var confirmingDoseMedication: MedicationItem? = nil

    // UC-11 Delete Medication Confirmation State
    @State private var medicationToDelete: MedicationItem? = nil
    @State private var showingDeleteConfirmationAlert = false

    // UC-7 Adherence Report State
    @State private var showingReportSheet = false

    public init(identity: UserIdentity) {
        self.identity = identity
    }

    public var body: some View {
        NavigationStack {
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

                    // 2.5 Adherence Weekly Quick Banner (UC-7)
                    Section {
                        adherenceQuickBanner
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    // 3. Active Medication or All Doses Completed
                    activeMedicationSection

                    // 4. Daily Schedule
                    upcomingDosesSection

                    // 5. Caregivers System List
                    caregiversSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.dawaiBackground.ignoresSafeArea())

                // Notification Toast (UC-2 S#8 & UC-3 S#8)
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
                    .preferredColorScheme(ThemeService.shared.colorScheme)
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
            .sheet(item: $confirmingDoseMedication) { med in
                DoseConfirmationSheet(medication: med, currentUser: identity)
                    .preferredColorScheme(ThemeService.shared.colorScheme)
            }
            .alert(
                relationshipService.activeRelationships.isEmpty
                    ? "تأكيد حذف دواء \"\(medicationToDelete?.name ?? "")\""
                    : "طلب حذف دواء \"\(medicationToDelete?.name ?? "")\"",
                isPresented: $showingDeleteConfirmationAlert
            ) {
                Button(
                    relationshipService.activeRelationships.isEmpty ? "حذف" : "إرسال طلب الحذف",
                    role: .destructive
                ) {
                    if let med = medicationToDelete {
                        if relationshipService.activeRelationships.isEmpty {
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
                if relationshipService.activeRelationships.isEmpty {
                    Text("هل أنت متأكد من رغبتك في حذف هذا الدواء؟ سيتم إلغاء جميع التذكيرات وإزالته من جدولك نهائياً.")
                } else {
                    Text("هل أنت متأكد من رغبتك في حذف هذا الدواء؟ سيتم إرسال إشعار لمقدم الرعاية للموافقة على حذفه نهائياً من جدولك.")
                }
            }
            .onAppear {
                medicationService.refreshDerivedState()
                themeService.applyThemeToApp()
                Task {
                    await medicationService.requestNotificationPermissionIfNeeded()
                }
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

            // Reports Button (UC-7 S#1: Application navigation access)
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
            .accessibilityLabel("تقرير الالتزام الدوائي")

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

    // MARK: - 2. Hero Dose Counter Card
    @ViewBuilder
    private var heroDoseCounterView: some View {
        let remaining = medicationService.remainingDoses
        let todayCount = medicationService.todayMedications.count
        let totalCount = medicationService.medications.count

        HStack(spacing: 10) {
            Spacer()

            if todayCount == 0 && totalCount > 0 {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                Text("لا توجد جرعات مجدولة لليوم")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if remaining == 0 && todayCount > 0 {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                Text("أكملت جميع جرعات اليوم")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Image(systemName: "pills.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.9))

                Text(doseCounterText(remaining: remaining))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer()
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: (todayCount == 0 && totalCount > 0)
                            ? [Color.dawaiPrimary.opacity(0.85), Color.dawaiPrimary]
                            : ((remaining == 0 && todayCount > 0)
                                ? [Color.dawaiTaken, Color(red: 14.0 / 255.0, green: 112.0 / 255.0, blue: 80.0 / 255.0)]
                                : [Color.dawaiPrimary, Color.dawaiPrimary.opacity(0.88)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
    }

    private func doseCounterText(remaining: Int) -> String {
        switch remaining {
        case 0:
            return "لا توجد جرعات متبقية اليوم"
        case 1:
            return "بقي جرعة واحدة لليوم"
        case 2:
            return "بقي جرعتان لليوم"
        default:
            return "بقي \(remaining) جرعات لليوم"
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
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(.primary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("الالتزام الأسبوعي")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text(report.tier.titleArabic)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(report.tier.color)
                            }
                            Text("تم تناول \(report.totalTaken) من \(report.totalScheduled) جرعة • اضغط لعرض التقرير الكامل")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
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
            if medicationService.todayMedications.isEmpty && !medicationService.medications.isEmpty {
                // UC-12 Alternate Course S#1: No medications scheduled for the current day
                noMedicationsTodayCard
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if medicationService.remainingDoses == 0 && !medicationService.todayMedications.isEmpty {
                // When all doses for today are taken: display all medications in native iOS list rows
                allDosesCompletedRows
            } else if let activeMedication = medicationService.activeMedication {
                activeMedicationCard(activeMedication)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    // Swipe right-to-left in Arabic RTL (leading edge) -> Delete Action
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            medicationToDelete = activeMedication
                            showingDeleteConfirmationAlert = true
                        } label: {
                            Label("حذف", systemImage: "trash")
                        }
                    }
                    // Swipe left-to-right in Arabic RTL (trailing edge) -> Edit Action
                    .swipeActions(edge: .trailing) {
                        Button {
                            editingMedication = activeMedication
                        } label: {
                            Label("تعديل", systemImage: "pencil")
                        }
                        .tint(Color.dawaiPrimary)
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
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
                .textCase(nil)

            Spacer()

            Button {
                showingAddMedicationSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
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
        ForEach(medicationService.medications) { med in
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.dawaiTaken)

                VStack(alignment: .leading, spacing: 2) {
                    Text(med.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("\(med.dosage) • \(med.timeString)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if med.isPendingDeletion {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 10, weight: .bold))
                        Text("بانتظار الموافقة")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color.dawaiWarning)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.dawaiWarningBackground, in: Capsule())
                } else {
                    Text("تم أخذها")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.dawaiTaken)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.dawaiTakenBadgeBackground, in: Capsule())
                }

                Button {
                    editingMedication = med
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("تعديل دواء \(med.name)")
            }
            .padding(.vertical, 4)
            // Swipe right-to-left in Arabic RTL (leading edge) -> Delete Action
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    medicationToDelete = med
                    showingDeleteConfirmationAlert = true
                } label: {
                    Label("حذف", systemImage: "trash")
                }
            }
            // Swipe left-to-right in Arabic RTL (trailing edge) -> Edit Action
            .swipeActions(edge: .trailing) {
                Button {
                    editingMedication = med
                } label: {
                    Label("تعديل", systemImage: "pencil")
                }
                .tint(Color.dawaiPrimary)
            }
        }
    }

    // MARK: - Active Medication Single Card (When Doses Remain)
    @ViewBuilder
    private func activeMedicationCard(_ activeMedication: MedicationItem) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                // Pill Icon Frame on RIGHT (FIRST in HStack)
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(activeMedication.isTaken ? Color.dawaiTakenBadgeBackground : Color.dawaiPrimary.opacity(0.12))
                        .frame(width: 68, height: 68)

                    Image(systemName: activeMedication.isTaken ? "checkmark.circle.fill" : "pill.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(activeMedication.isTaken ? Color.dawaiTaken : Color.dawaiPrimary)
                        .rotationEffect(activeMedication.isTaken ? .degrees(0) : .degrees(-45))
                }

                // Details in CENTER
                VStack(alignment: .leading, spacing: 4) {
                    Text(activeMedication.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(activeMedication.dosage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Text(activeMedication.timeString)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(activeMedication.isTaken ? Color.dawaiTaken : Color.dawaiPrimary)

                        if activeMedication.isTaken {
                            Text("• تم أخذها")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.dawaiTaken)
                        }
                    }
                }

                Spacer()

                // Edit Button on LEFT (UC-3: Pencil opens Edit Medication)
                Button {
                    editingMedication = activeMedication
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
                .accessibilityLabel("تعديل الدواء")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, activeMedication.isTaken ? 16 : 0)

            // Dose Confirmation Action Button (Shown only when NOT taken - UC-4 & UC-6)
            if !activeMedication.isTaken {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        medicationService.confirmDoseTaken(id: activeMedication.id, patient: identity)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                        Text("اخذت الدواء")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.dawaiPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(
            activeMedication.isTaken
                ? Color.dawaiTakenBackground
                : Color.clear
        )
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    activeMedication.isTaken ? Color.dawaiTakenBorder : Color.dawaiGlassBorder,
                    lineWidth: activeMedication.isTaken ? 1.5 : 1
                )
        )
    }

    // MARK: - Empty Medications Fallback Card
    @ViewBuilder
    private var emptyMedicationsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "pill.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.dawaiPrimary)

            Text("لا توجد أدوية مجدولة")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)

            Text("اضغط على (+) في الأعلى لإضافة دواء وتحديد مواعيد الجرعات.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.ultraThinMaterial)
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
                .font(.system(size: 32))
                .foregroundStyle(Color.dawaiPrimary)

            Text("لا توجد أدوية مجدولة لليوم")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)

            Text("جميع أدويتك المسجلة مجدولة في أيام أخرى. اضغط على (+) لإضافة دواء جديد أو لتعديل المواعيد.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.ultraThinMaterial)
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
                    HStack(spacing: 12) {
                        // Medication Name & Dosage on RIGHT (Leading in RTL)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dose.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(dose.isTaken ? .secondary : .primary)

                            Text(dose.dosage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Status / Time in CENTER
                        if dose.isTaken {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text("تم أخذها")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(Color.dawaiTaken)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.dawaiTakenBadgeBackground, in: Capsule())
                        } else {
                            HStack(spacing: 5) {
                                Image(systemName: "clock")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(dose.timeString)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(Color.primary.opacity(0.75))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                        }

                        // Edit Button on LEFT (Trailing in RTL - allows editing or deleting)
                        Button {
                            if let med = medicationService.medications.first(where: { $0.id == dose.id }) {
                                editingMedication = med
                            } else {
                                editingMedication = MedicationItem(name: dose.name, dosage: dose.dosage, timeString: dose.timeString)
                            }
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("تعديل أو حذف دواء \(dose.name)")
                    }
                    .padding(.vertical, 4)
                    // Swipe right-to-left in Arabic RTL (leading edge) -> Delete Action
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            if let med = medicationService.medications.first(where: { $0.id == dose.id }) {
                                medicationToDelete = med
                                showingDeleteConfirmationAlert = true
                            }
                        } label: {
                            Label("حذف", systemImage: "trash")
                        }
                    }
                    // Swipe left-to-right in Arabic RTL (trailing edge) -> Edit Action
                    .swipeActions(edge: .trailing) {
                        Button {
                            if let med = medicationService.medications.first(where: { $0.id == dose.id }) {
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
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
        }
    }

    // MARK: - 5. Caregivers Section (Native iOS Grouped List)
    @ViewBuilder
    private var caregiversSection: some View {
        let accepted = deduplicateInvitations(relationshipService.outgoingInvitations.filter { $0.status == .accepted })
        let active = relationshipService.activeRelationships.filter { $0.patientId == identity.id }
        let incoming = deduplicateInvitations(relationshipService.incomingInvitations.filter { $0.status == .pending })
        let pending = deduplicateInvitations(relationshipService.outgoingInvitations.filter { $0.status == .pending })
        let isEmpty = accepted.isEmpty && active.isEmpty && incoming.isEmpty && pending.isEmpty

        Section {
            if isEmpty {
                fallbackCaregiverCard
            } else {
                ForEach(accepted) { invite in
                    acceptedCaregiverCard(invite: invite)
                }

                ForEach(incoming) { inc in
                    incomingCaregiverCard(incoming: inc)
                }

                ForEach(pending) { invite in
                    pendingCaregiverCard(invite: invite)
                }

                ForEach(active) { rel in
                    activeCaregiverCard(rel: rel)
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
        HStack {
            Text("مقدمي الرعاية")
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
                    .background(Color.dawaiPrimary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("إنشاء دعوة مقدم رعاية")
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dawaiTaken)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cleanDisplayName(invite.recipientDisplayName ?? "مقدم رعاية"))
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
    private func activeCaregiverCard(rel: ActiveRelationship) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.dawaiPrimary.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "person.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.dawaiPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cleanDisplayName(rel.caregiverDisplayName))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("مقدم رعاية • متابع للأدوية")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Text("نشط")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.dawaiTaken)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.dawaiTakenBadgeBackground, in: Capsule())

                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                withAnimation {
                    relationshipService.disconnect(relationshipId: rel.id)
                }
            } label: {
                Label("إلغاء الارتباط", systemImage: "person.crop.circle.badge.xmark")
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
    private func pendingCaregiverCard(invite: ConnectionInvitation) -> some View {
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
                Text("دعوة مقدم رعاية")
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
                    medicationService.showToast("تم نسخ رمز الدعوة بنجاح")
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

    @ViewBuilder
    private var fallbackCaregiverCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .systemGray6))
                    .frame(width: 36, height: 36)
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("لا يوجد مقدمي رعاية")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)

                Text("أضف مقدم رعاية لمتابعة مواعيد أدويتك")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showingCreateInvitationSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("إضافة")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.dawaiPrimary.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.dawaiPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
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

// MARK: - Use-Case 4 (UC-4) Step 5 & Use-Case 6 (UC-6) Step 6: Dose Confirmation Sheet
public struct DoseConfirmationSheet: View {
    public let medication: MedicationItem
    public let currentUser: UserIdentity
    public var onConfirmed: (() -> Void)? = nil
    public var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var medicationService = MedicationService.shared
    @ObservedObject private var themeService = ThemeService.shared

    @State private var hasConfirmed: Bool = false
    @State private var isProcessing: Bool = false

    public init(
        medication: MedicationItem,
        currentUser: UserIdentity,
        onConfirmed: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.medication = medication
        self.currentUser = currentUser
        self.onConfirmed = onConfirmed
        self.onDismiss = onDismiss
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
                        if hasConfirmed || medication.isTaken {
                            Label("تم تأكيد الجرعة بنجاح", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.dawaiTaken)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.dawaiTakenBadgeBackground, in: Capsule())
                        } else {
                            Label("حان موعد الجرعة الآن", systemImage: "bell.badge.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.dawaiWarning)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.dawaiWarningBadgeBackground, in: Capsule())
                        }

                        Text(medication.name)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 10) {
                            // Dosage Pill
                            HStack(spacing: 5) {
                                Image(systemName: "pills.fill")
                                    .font(.system(size: 13))
                                Text(medication.dosage.westernNumerals)
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(Color.dawaiPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.dawaiPrimary.opacity(0.12), in: Capsule())

                            // Time Pill
                            HStack(spacing: 5) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 13))
                                Text(medication.timeString.westernNumerals)
                                    .font(.system(size: 15, weight: .semibold))
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
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.dawaiPrimary)
                }
            }
        }
    }

    // MARK: - 1. Hero Image / Icon View
    @ViewBuilder
    private var heroImageView: some View {
        if let imageData = medication.imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.dawaiGlassBorder, lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        } else {
            ZStack {
                Circle()
                    .fill(hasConfirmed || medication.isTaken ? Color.dawaiTakenBadgeBackground : Color.dawaiPrimary.opacity(0.12))
                    .frame(width: 110, height: 110)

                Image(systemName: hasConfirmed || medication.isTaken ? "checkmark.circle.fill" : "pills.circle.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(hasConfirmed || medication.isTaken ? Color.dawaiTaken : Color.dawaiPrimary)
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(medication.frequency) • \(medication.days.joined(separator: "، "))")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Divider()

            // Instructions (if present)
            if let instructions = medication.instructions, !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("تعليمات الاستخدام", systemImage: "info.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.dawaiPrimary)

                    Text(instructions)
                        .font(.system(size: 15, weight: .medium))
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(medication.duration)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
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
            if hasConfirmed || medication.isTaken {
                // Already confirmed state
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22))
                    Text("تم تأكيد أخذ الجرعة")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.dawaiTaken)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color.dawaiTaken.opacity(0.25), radius: 8, x: 0, y: 4)
            } else {
                // Prominent "I Took It" Button (UC-4 S#5 & S#6)
                Button {
                    confirmDose()
                } label: {
                    HStack(spacing: 10) {
                        if isProcessing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .bold))
                            Text("أخذت الجرعة")
                                .font(.system(size: 19, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.dawaiPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.dawaiPrimary.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)

                // Secondary "Remind me later" Button
                Button {
                    dismiss()
                    onDismiss?()
                } label: {
                    Text("سآخذها لاحقاً")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Action: Confirm Dose Taken (UC-6)
    private func confirmDose() {
        isProcessing = true
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            medicationService.confirmDoseTaken(id: medication.id, patient: currentUser)
            hasConfirmed = true
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
