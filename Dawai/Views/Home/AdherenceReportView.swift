//
//  AdherenceReportView.swift
//  Dawai
//
//  Use-Case 7 (UC-7): View Adherence Report
//  Presents a weekly medication adherence report with percentage summaries,
//  visual trend graphs, permission validation, week period filtering,
//  and daily dose log breakdowns.
//

import SwiftUI

public struct AdherenceReportView: View {
    let currentUser: UserIdentity
    let initialPatientId: String?
    let initialPatientName: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var adherenceService = AdherenceService.shared
    @ObservedObject private var relationshipService = RelationshipService.shared
    @ObservedObject private var themeService = ThemeService.shared
    @ObservedObject private var demoMode = DemoModeService.shared

    // Selected state
    @State private var selectedPeriodIndex: Int = 0
    @State private var selectedPatientId: String = ""
    @State private var selectedPatientName: String = ""
    @State private var selectedDayDate: Date? = nil
    @State private var showingShareSheet = false
    @State private var shareText: String = ""

    public init(
        currentUser: UserIdentity,
        targetPatientId: String? = nil,
        targetPatientName: String? = nil
    ) {
        self.currentUser = currentUser
        self.initialPatientId = targetPatientId
        self.initialPatientName = targetPatientName
    }

    // MARK: - Computed Properties
    private var availablePeriods: [WeekPeriod] {
        adherenceService.availableWeekPeriods(count: 4)
    }

    private var currentPeriod: WeekPeriod {
        guard selectedPeriodIndex >= 0 && selectedPeriodIndex < availablePeriods.count else {
            return availablePeriods.first ?? WeekPeriod(
                id: 0,
                startDate: Date(),
                endDate: Date(),
                titleArabic: "هذا الأسبوع",
                dateRangeString: ""
            )
        }
        return availablePeriods[selectedPeriodIndex]
    }

    /// Access permission check (UC-7 S#2)
    private var accessVerification: (isAuthorized: Bool, errorReason: String?) {
        adherenceService.verifyAccess(actor: currentUser, targetPatientId: selectedPatientId)
    }

    /// Generated report for current patient and selected period (UC-7 S#4)
    private var report: WeeklyAdherenceReport {
        adherenceService.generateWeeklyReport(
            patientId: selectedPatientId,
            patientDisplayName: selectedPatientName,
            period: currentPeriod
        )
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.dawaiBackground.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 20) {
                        // 1. Patient Selector Header (only when Caregiver has linked or demo beneficiaries)
                        if currentUser.role == .caregiver &&
                            (!relationshipService.activeRelationships.filter({ $0.caregiverId == currentUser.id && $0.isActive }).isEmpty || !demoMode.beneficiaries.isEmpty) {
                            caregiverPatientSelector
                        }

                        // 2. Empty state when caregiver has no linked patients yet
                        if currentUser.role == .caregiver && selectedPatientId.isEmpty {
                            noLinkedBeneficiariesCard
                        } else if !accessVerification.isAuthorized {
                            // Permission check warning (if unauthorized)
                            unauthorizedAccessCard
                        } else {
                            // 3. Week Period Selector (UC-7 S#3)
                            weekPeriodSelector

                            if !report.hasSufficientData {
                                // Post-condition: Insufficient data message
                                insufficientDataView
                            } else {
                                // 4. Hero Weekly Adherence Percentage Card (UC-7 S#5)
                                heroAdherenceCard

                                // 5. Stat Metric Counters
                                metricCountersRow

                                // 6. Visual Trend Graph (Weekly Bar Chart) (UC-7 S#5)
                                visualTrendGraphCard

                                // 7. Medication Performance Breakdown
                                medicationBreakdownCard

                                // 8. Daily Dose History Timeline
                                dailyDoseLogCard
                            }
                        }

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale.dawaiArabic)
            .navigationTitle("تقرير الالتزام الدوائي")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("إغلاق") {
                        dismiss()
                    }
                    .dawaiFont(size: 16, weight: .semibold)
                    .foregroundStyle(Color.dawaiPrimary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if accessVerification.isAuthorized && report.hasSufficientData {
                        ShareLink(
                            item: generatedReportShareText,
                            subject: Text("تقرير الالتزام الدوائي الأسبوعي")
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .dawaiFont(size: 16, weight: .semibold)
                                .foregroundStyle(Color.dawaiPrimary)
                        }
                        .accessibilityLabel("مشاركة التقرير")
                    }
                }
            }
            .onAppear {
                MedicationService.shared.refreshDerivedState()
                setupInitialPatient()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    MedicationService.shared.refreshDerivedState()
                }
            }
            .preferredColorScheme(themeService.colorScheme)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale.dawaiArabic)
    }

    // MARK: - Patient Initialization
    @MainActor
    private func setupInitialPatient() {
        if currentUser.role == .patient {
            selectedPatientId = currentUser.id
            selectedPatientName = currentUser.displayName
        } else {
            // Caregiver mode: default to target if provided
            if let pid = initialPatientId, !pid.isEmpty {
                selectedPatientId = pid
                selectedPatientName = initialPatientName ?? "المستفيد"
            } else if let firstActive = relationshipService.activeRelationships.first(where: { $0.caregiverId == currentUser.id && $0.isActive }) {
                selectedPatientId = firstActive.patientId
                selectedPatientName = firstActive.patientDisplayName
            } else if let demoFirst = demoMode.beneficiaries.first {
                selectedPatientId = demoFirst.patientId ?? demoFirst.id.uuidString
                selectedPatientName = demoFirst.name
            } else {
                selectedPatientId = ""
                selectedPatientName = ""
            }
        }
    }

    // MARK: - 1. Caregiver Patient Selector (UC-7 S#2)
    @ViewBuilder
    private var caregiverPatientSelector: some View {
        let activeRels = relationshipService.activeRelationships.filter { $0.caregiverId == currentUser.id && $0.isActive }
        let demoBeneficiaries = demoMode.beneficiaries

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("المستفيد المحدد", systemImage: "person.circle.fill")
                    .dawaiFont(size: 14, weight: .semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                if accessVerification.isAuthorized {
                    Label("مصرح بالاطلاع", systemImage: "checkmark.seal.fill")
                        .dawaiFont(size: 12, weight: .bold)
                        .foregroundStyle(Color.dawaiTaken)
                }
            }

            if activeRels.isEmpty && demoBeneficiaries.isEmpty {
                Text("لا يوجد مستفيدون مرتبطون لعرض تقاريرهم حالياً.")
                    .dawaiFont(size: 13, weight: .medium)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Connected active relationships
                        ForEach(activeRels) { rel in
                            patientChip(id: rel.patientId, name: rel.patientDisplayName, isConnected: true)
                        }

                        // Demo beneficiaries if enabled in DEBUG and no active relationship is available
                        if activeRels.isEmpty {
                            ForEach(demoBeneficiaries) { ben in
                                patientChip(id: ben.patientId ?? ben.id.uuidString, name: ben.name, isConnected: true)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.dawaiGlassBorder, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func patientChip(id: String, name: String, isConnected: Bool) -> some View {
        let isSelected = selectedPatientId == id || (selectedPatientName == name)
        Button {
            selectedPatientId = id
            selectedPatientName = name
            selectedDayDate = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "person.fill")
                    .dawaiFont(size: 13)
                Text(name)
                    .dawaiFont(size: 14, weight: isSelected ? .bold : .medium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.dawaiPrimary : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.dawaiPrimary : Color.dawaiGlassBorder, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Empty & Unauthorized Cards
    @ViewBuilder
    private var noLinkedBeneficiariesCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.slash")
                .dawaiFont(size: 42)
                .foregroundStyle(Color.secondary.opacity(0.75))

            Text("لا يوجد مستفيدون مرتبطون")
                .dawaiFont(size: 18, weight: .bold)
                .foregroundStyle(.primary)

            Text("يرجى إرسال دعوة ربط لمستفيد وقبولها أولاً لتتمكن من متابعة تقارير الالتزام الدوائي الخاصة به.")
                .dawaiFont(size: 14)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.dawaiGlassFill)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.dawaiGlassTint)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var unauthorizedAccessCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                .dawaiFont(size: 40)
                .foregroundStyle(Color.dawaiWarning)

            Text("غير مصرح بالاطلاع على التقرير")
                .dawaiFont(size: 18, weight: .bold)
                .foregroundStyle(.primary)

            Text(accessVerification.errorReason ?? "لا تملك الصلاحية للوصول إلى هذا التقرير.")
                .dawaiFont(size: 14)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.dawaiWarning.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - 3. Week Period Selector (UC-7 S#3)
    @ViewBuilder
    private var weekPeriodSelector: some View {
        VStack(spacing: 10) {
            // Period segments
            HStack(spacing: 6) {
                ForEach(0..<availablePeriods.count, id: \.self) { idx in
                    let period = availablePeriods[idx]
                    let isSelected = selectedPeriodIndex == idx

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedPeriodIndex = idx
                            selectedDayDate = nil
                        }
                    } label: {
                        Text(period.titleArabic)
                            .dawaiFont(size: 13, weight: isSelected ? .bold : .medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.dawaiPrimary : Color.clear)
                            )
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.7))
            )

            // Date span banner with stepper navigation
            HStack {
                Button {
                    if selectedPeriodIndex < availablePeriods.count - 1 {
                        withAnimation {
                            selectedPeriodIndex += 1
                            selectedDayDate = nil
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .dawaiFont(size: 14, weight: .bold)
                        .foregroundStyle(selectedPeriodIndex < availablePeriods.count - 1 ? Color.dawaiPrimary : Color.secondary.opacity(0.3))
                        .frame(width: 32, height: 32)
                }
                .disabled(selectedPeriodIndex >= availablePeriods.count - 1)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .dawaiFont(size: 14)
                        .foregroundStyle(Color.dawaiPrimary)
                    Text(currentPeriod.dateRangeString)
                        .dawaiFont(size: 14, weight: .semibold)
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button {
                    if selectedPeriodIndex > 0 {
                        withAnimation {
                            selectedPeriodIndex -= 1
                            selectedDayDate = nil
                        }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .dawaiFont(size: 14, weight: .bold)
                        .foregroundStyle(selectedPeriodIndex > 0 ? Color.dawaiPrimary : Color.secondary.opacity(0.3))
                        .frame(width: 32, height: 32)
                }
                .disabled(selectedPeriodIndex <= 0)
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Post-condition: Insufficient Data State
    @ViewBuilder
    private var insufficientDataView: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.doc.horizontal")
                .dawaiFont(size: 44)
                .foregroundStyle(Color.secondary.opacity(0.75))

            Text("لا توجد بيانات للتقرير بعد")
                .dawaiFont(size: 19, weight: .bold)
                .foregroundStyle(.primary)

            Text(
                currentUser.role == .patient
                    ? "لم يتم تسجيل أي جرعات خلال فترة \(currentPeriod.titleArabic) (\(currentPeriod.dateRangeString)). ستظهر إحصائيات التزامك هنا تلقائياً بعد تسجيل جرعاتك."
                    : "لم يتم تسجيل أي جرعات لـ \(selectedPatientName) خلال فترة \(currentPeriod.titleArabic) (\(currentPeriod.dateRangeString)) حتى الآن."
            )
            .dawaiFont(size: 14)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
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

    // MARK: - 4. Hero Weekly Adherence Percentage Card (UC-7 S#5)
    @ViewBuilder
    private var heroAdherenceCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                // Circular Progress Gauge
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 10)
                        .frame(width: 96, height: 96)

                    Circle()
                        .trim(from: 0.0, to: min(1.0, CGFloat(report.adherencePercentage / 100.0)))
                        .stroke(
                            LinearGradient(
                                colors: [report.tier.color, report.tier.color.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 96, height: 96)
                        .animation(.easeOut(duration: 0.6), value: report.adherencePercentage)

                    VStack(spacing: 0) {
                        Text("\(Int(round(report.adherencePercentage)))%")
                            .dawaiFont(size: 24, weight: .heavy, design: .rounded)
                            .foregroundStyle(.primary)
                        Text("الالتزام")
                            .dawaiFont(size: 11, weight: .medium)
                            .foregroundStyle(.secondary)
                    }
                }

                // Tier badge and description
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(report.tier.titleArabic)
                            .dawaiFont(size: 18, weight: .bold)
                            .foregroundStyle(report.tier.color)

                        Spacer()

                        if let trend = report.trendVsPreviousWeek {
                            trendPill(trend: trend)
                        }
                    }

                    Text(report.tierMessageArabic)
                        .dawaiFont(size: 13)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("تم تناول \(report.totalTaken) من أصل \(report.totalScheduled) جرعة مجدولة")
                            .dawaiFont(size: 12, weight: .bold)
                            .foregroundStyle(.primary.opacity(0.85))

                        Text("منها \(report.totalTakenLate) متأخرة و \(report.totalMissed) فائتة")
                            .dawaiFont(size: 12, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(report.tier.color.opacity(0.25), lineWidth: 1.5)
                )
        )
    }

    @ViewBuilder
    private func trendPill(trend: Double) -> some View {
        let isPositive = trend >= 0
        HStack(spacing: 3) {
            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                .dawaiFont(size: 10, weight: .bold)
            Text("\(isPositive ? "+" : "")\(Int(round(trend)))%")
                .dawaiFont(size: 11, weight: .bold)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(isPositive ? Color.dawaiTaken.opacity(0.15) : Color.dawaiWarning.opacity(0.15))
        )
        .foregroundStyle(isPositive ? Color.dawaiTaken : Color.dawaiWarning)
    }

    // MARK: - 5. Metric Counters Row
    @ViewBuilder
    private var metricCountersRow: some View {
        HStack(spacing: 6) {
            metricItem(title: "في الموعد", count: report.totalTakenOnTime, color: Color.dawaiTaken, icon: "checkmark.circle.fill")
            metricItem(title: "متأخرة", count: report.totalTakenLate, color: Color.dawaiWarning, icon: "clock.badge.exclamationmark.fill")
            metricItem(title: "فائتة", count: report.totalMissed, color: Color(red: 220.0 / 255.0, green: 53.0 / 255.0, blue: 69.0 / 255.0), icon: "xmark.circle.fill")
            metricItem(title: "الإجمالي", count: report.totalScheduled, color: Color.dawaiPrimary, icon: "pills.fill")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func metricItem(title: String, count: Int, color: Color, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .dawaiFont(size: 11)
                Text(title)
                    .dawaiFont(size: 11, weight: .medium)
            }
            .foregroundStyle(.secondary)

            Text("\(count)")
                .dawaiFont(size: 20, weight: .bold, design: .rounded)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.dawaiGlassBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - 6. Visual Trend Graph (Weekly Bar Chart) (UC-7 S#5)
    @ViewBuilder
    private var visualTrendGraphCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("الرسم البياني للالتزام اليومي")
                        .dawaiFont(size: 16, weight: .bold)
                        .foregroundStyle(.primary)
                    Text("اضغط على أي يوم لعرض تفاصيل جرعاته")
                        .dawaiFont(size: 12)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.dawaiTaken)
                        .frame(width: 8, height: 8)
                    Text("الهدف 80%")
                        .dawaiFont(size: 11, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }

            // Legend for stacked bar segments
            HStack(spacing: 14) {
                barLegendItem(title: "في الموعد", color: Color.dawaiTaken)
                barLegendItem(title: "متأخرة", color: Color.dawaiWarning)
                barLegendItem(title: "فائتة", color: DoseStatus.missed.color)
                Spacer()
            }

            // Interactive Weekly Bar Graph
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(report.dailySummaries) { day in
                    dayBarView(day: day)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Dotted 80% line explanation
            HStack {
                Text("المعدل الأسبوعي العام: \(Int(round(report.adherencePercentage)))%")
                    .dawaiFont(size: 12, weight: .bold)
                    .foregroundStyle(report.tier.color)

                Spacer()

                if selectedDayDate != nil {
                    Button {
                        withAnimation {
                            selectedDayDate = nil
                        }
                    } label: {
                        Text("عرض الأسبوع بالكامل")
                            .dawaiFont(size: 11, weight: .bold)
                            .foregroundStyle(Color.dawaiPrimary)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.dawaiGlassBorder, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func barLegendItem(title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .dawaiFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func dayBarView(day: DailyAdherenceSummary) -> some View {
        let isSelected = selectedDayDate != nil && Calendar.current.isDate(day.date, inSameDayAs: selectedDayDate!)
        let segments = dayBarSegments(for: day, totalHeight: 85.0)

        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if isSelected {
                    selectedDayDate = nil
                } else {
                    selectedDayDate = day.date
                }
            }
        } label: {
            VStack(spacing: 5) {
                // Top percentage label
                if !day.isFuture && day.scheduledCount > 0 {
                    Text("\(Int(round(day.percentage)))%")
                        .dawaiFont(size: 9, weight: .bold, design: .rounded)
                        .foregroundStyle(isSelected ? Color.dawaiPrimary : Color.secondary)
                        .frame(height: 12)
                } else {
                    Text("-")
                        .dawaiFont(size: 9, weight: .medium)
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .frame(height: 12)
                }

                // Segmented vertical bar capsule (On-time Green / Late Orange / Missed Red)
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.6))
                        .frame(width: 22, height: 85)

                    if day.isFuture || day.scheduledCount == 0 || segments.isEmpty {
                        Capsule()
                            .fill(Color.secondary.opacity(day.isFuture ? 0.16 : 0.22))
                            .frame(width: 22, height: 6)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(segments) { segment in
                                Rectangle()
                                    .fill(segment.color)
                                    .frame(width: 22, height: segment.height)
                            }
                        }
                        .frame(width: 22, height: 85)
                        .clipShape(Capsule())
                    }
                }
                .frame(width: 22, height: 85)

                // Day name & indicator
                VStack(spacing: 2) {
                    Text(day.dayShortArabic)
                        .dawaiFont(size: 12, weight: isSelected || day.isToday ? .bold : .medium)
                        .foregroundStyle(isSelected ? Color.dawaiPrimary : (day.isToday ? Color.primary : Color.secondary))

                    Circle()
                        .fill(day.isToday ? Color.dawaiPrimary : Color.clear)
                        .frame(width: 4, height: 4)
                }

                // Under-column Late & Missed count badges
                VStack(spacing: 2) {
                    if !day.isFuture {
                        if day.takenLateCount > 0 {
                            dayCountBadge(
                                text: "\(day.takenLateCount) متأخرة",
                                color: Color.dawaiWarning
                            )
                        }
                        if day.missedCount > 0 {
                            dayCountBadge(
                                text: "\(day.missedCount) فائتة",
                                color: DoseStatus.missed.color
                            )
                        }
                    }
                }
                .frame(height: 32, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.dawaiPrimary.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func dayCountBadge(text: String, color: Color) -> some View {
        Text(text)
            .dawaiFont(size: 8.5, weight: .bold, design: .rounded)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }

    private struct DayBarSegment: Identifiable {
        let id: String
        let count: Int
        let color: Color
        let height: CGFloat
    }

    private func dayBarSegments(for day: DailyAdherenceSummary, totalHeight: CGFloat) -> [DayBarSegment] {
        let raw: [(id: String, count: Int, color: Color)] = [
            ("missed", day.missedCount, DoseStatus.missed.color),
            ("late", day.takenLateCount, Color.dawaiWarning),
            ("onTime", day.takenOnTimeCount, Color.dawaiTaken)
        ]
        let active = raw.filter { $0.count > 0 }
        guard !active.isEmpty else { return [] }

        let totalCount = active.reduce(0) { $0 + $1.count }
        let minSegmentHeight: CGFloat = 14.0
        let reserved = minSegmentHeight * CGFloat(active.count)
        let distributable = max(0, totalHeight - reserved)

        return active.map { segment in
            let share = CGFloat(segment.count) / CGFloat(max(totalCount, 1))
            let height = minSegmentHeight + (distributable * share)
            return DayBarSegment(id: segment.id, count: segment.count, color: segment.color, height: height)
        }
    }

    // MARK: - 7. Medication Performance Breakdown
    @ViewBuilder
    private var medicationBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("الالتزام حسب كل دواء")
                .dawaiFont(size: 16, weight: .bold)
                .foregroundStyle(.primary)

            VStack(spacing: 12) {
                ForEach(report.medicationSummaries) { med in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(med.name)
                                    .dawaiFont(size: 15, weight: .bold)
                                    .foregroundStyle(.primary)
                                Text(med.dosage)
                                    .dawaiFont(size: 12)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(Int(round(med.percentage)))%")
                                    .dawaiFont(size: 16, weight: .heavy, design: .rounded)
                                    .foregroundStyle(med.percentage >= 80 ? Color.dawaiTaken : Color.dawaiWarning)
                                Text("\(med.takenCount) من \(med.scheduledCount) جرعة")
                                    .dawaiFont(size: 11)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Progress Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.8))
                                    .frame(height: 6)

                                Capsule()
                                    .fill(med.percentage >= 80 ? Color.dawaiTaken : Color.dawaiWarning)
                                    .frame(width: max(6, geo.size.width * CGFloat(med.percentage / 100.0)), height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.5))
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.dawaiGlassBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - 8. Daily Dose History Timeline
    @ViewBuilder
    private var dailyDoseLogCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(selectedDayDate != nil ? "سجل جرعات اليوم المحدد" : "سجل الجرعات التفصيلي للأسبوع")
                    .dawaiFont(size: 16, weight: .bold)
                    .foregroundStyle(.primary)

                Spacer()

                if let sel = selectedDayDate {
                    let f = DateFormatter()
                    let _ = f.locale = Locale.dawaiArabic
                    let _ = f.dateFormat = "EEEE d MMMM"
                    Text(f.string(from: sel).westernNumerals)
                        .dawaiFont(size: 12, weight: .semibold)
                        .foregroundStyle(Color.dawaiPrimary)
                }
            }

            let daysToDisplay: [DailyAdherenceSummary] = {
                if let sel = selectedDayDate {
                    return report.dailySummaries.filter { Calendar.current.isDate($0.date, inSameDayAs: sel) }
                } else {
                    return report.dailySummaries.filter { !$0.isFuture && !$0.records.isEmpty }
                }
            }()

            if daysToDisplay.isEmpty || daysToDisplay.allSatisfy({ $0.records.isEmpty }) {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "tray")
                            .dawaiFont(size: 24)
                            .foregroundStyle(.secondary)
                        Text("لا توجد سجلات جرعات لهذا اليوم")
                            .dawaiFont(size: 13)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(daysToDisplay) { day in
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(day.dayNameArabic) • \(formatShortDate(day.date))")
                                        .dawaiFont(size: 13, weight: .bold)
                                        .foregroundStyle(Color.dawaiPrimary)

                                    Spacer()

                                    Text("\(day.takenCount)/\(day.scheduledCount) جرعة")
                                        .dawaiFont(size: 12, weight: .semibold)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 10) {
                                    Text("في الموعد: \(day.takenOnTimeCount)")
                                        .foregroundStyle(Color.dawaiTaken)
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Text("متأخرة: \(day.takenLateCount)")
                                        .foregroundStyle(Color.dawaiWarning)
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Text("فائتة: \(day.missedCount)")
                                        .foregroundStyle(DoseStatus.missed.color)
                                }
                                .dawaiFont(size: 11, weight: .semibold)
                            }

                            ForEach(day.records) { record in
                                doseRecordRow(record: record)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.5))
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.dawaiGlassBorder, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func doseRecordRow(record: DoseRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: record.status.systemIcon)
                .dawaiFont(size: 18)
                .foregroundStyle(record.status.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.medicationName)
                    .dawaiFont(size: 14, weight: .bold)
                    .foregroundStyle(.primary)

                Text(record.dosage)
                    .dawaiFont(size: 12)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(record.status.titleArabic)
                        .dawaiFont(size: 11, weight: .bold)
                    if record.delayMinutes > 0 && record.status == .takenLate {
                        Text("(\(record.delayMinutes) د تأخير)")
                            .dawaiFont(size: 10)
                    }
                }
                .foregroundStyle(record.status.color)

                Text(formatTime(record.scheduledDate))
                    .dawaiFont(size: 11)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers
    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.dawaiArabic
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: date).westernNumerals
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.dawaiArabic
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date).westernNumerals
    }

    private var generatedReportShareText: String {
        var text = "📊 تقرير الالتزام الدوائي الأسبوعي - تطبيق دواء\n"
        text += "المستفيد: \(report.patientDisplayName)\n"
        text += "الفترة: \(report.period.titleArabic) (\(report.period.dateRangeString))\n"
        text += "نسبة الالتزام العامة: \(Int(round(report.adherencePercentage)))% (\(report.tier.titleArabic))\n"
        text += "إجمالي الجرعات: \(report.totalScheduled) | في الموعد: \(report.totalTakenOnTime) | متأخرة: \(report.totalTakenLate) | فائتة: \(report.totalMissed)\n\n"
        text += "ملخص الأدوية:\n"
        for med in report.medicationSummaries {
            text += "- \(med.name) (\(med.dosage)): \(Int(round(med.percentage)))% (\(med.takenCount)/\(med.scheduledCount))\n"
        }
        text += "\nتم إنشاء التقرير عبر تطبيق دواء لسلامة ومتابعة الأدوية."
        return text
    }
}

// MARK: - Native iOS UIActivityViewController Wrapper for Sharing
struct ShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    AdherenceReportView(
        currentUser: UserIdentity(
            role: .patient,
            displayName: "سارة",
            keyFingerprint: "mock_fingerprint"
        )
    )
    .tint(Color.dawaiPrimary)
    .environment(\.layoutDirection, .rightToLeft)
}
