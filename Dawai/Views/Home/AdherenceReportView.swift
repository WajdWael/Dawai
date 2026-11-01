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
    @ObservedObject private var adherenceService = AdherenceService.shared
    @ObservedObject private var relationshipService = RelationshipService.shared
    @ObservedObject private var themeService = ThemeService.shared

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

                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Patient Selector Header (if Caregiver)
                        if currentUser.role == .caregiver {
                            caregiverPatientSelector
                        }

                        // 2. Permission check warning (if unauthorized)
                        if !accessVerification.isAuthorized {
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
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                            Text("إغلاق")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundStyle(Color.dawaiPrimary)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if accessVerification.isAuthorized && report.hasSufficientData {
                        Button {
                            prepareShareText()
                            showingShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.dawaiPrimary)
                        }
                        .accessibilityLabel("مشاركة التقرير")
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareActivityView(activityItems: [shareText])
            }
            .onAppear {
                setupInitialPatient()
            }
            .preferredColorScheme(themeService.colorScheme)
        }
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
            } else if let firstActive = relationshipService.activeRelationships.first(where: { $0.caregiverId == currentUser.id }) {
                selectedPatientId = firstActive.patientId
                selectedPatientName = firstActive.patientDisplayName
            } else if let demoFirst = HomeMockData.beneficiaries.first(where: { !$0.isInvitation }) {
                selectedPatientId = demoFirst.id.uuidString
                selectedPatientName = demoFirst.name
            } else {
                selectedPatientId = "default_patient"
                selectedPatientName = "المستفيد"
            }
        }
    }

    // MARK: - 1. Caregiver Patient Selector (UC-7 S#2)
    @ViewBuilder
    private var caregiverPatientSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("المستفيد المحدد", systemImage: "person.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if accessVerification.isAuthorized {
                    Label("مصرح بالاطلاع", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.dawaiTaken)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Connected active relationships
                    ForEach(relationshipService.activeRelationships.filter { $0.caregiverId == currentUser.id }) { rel in
                        patientChip(id: rel.patientId, name: rel.patientDisplayName, isConnected: true)
                    }

                    // Demo beneficiaries if no active relationship is available
                    if relationshipService.activeRelationships.isEmpty {
                        ForEach(HomeMockData.beneficiaries.filter { !$0.isInvitation }) { ben in
                            patientChip(id: ben.id.uuidString, name: ben.name, isConnected: true)
                        }
                    }
                }
                .padding(.vertical, 2)
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
                    .font(.system(size: 13))
                Text(name)
                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))
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

    // MARK: - 2. Unauthorized Access Card
    @ViewBuilder
    private var unauthorizedAccessCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.dawaiWarning)

            Text("غير مصرح بالاطلاع على التقرير")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)

            Text(accessVerification.errorReason ?? "لا تملك الصلاحية للوصول إلى هذا التقرير.")
                .font(.system(size: 14))
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
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(selectedPeriodIndex < availablePeriods.count - 1 ? Color.dawaiPrimary : Color.secondary.opacity(0.3))
                        .frame(width: 32, height: 32)
                }
                .disabled(selectedPeriodIndex >= availablePeriods.count - 1)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.dawaiPrimary)
                    Text(currentPeriod.dateRangeString)
                        .font(.system(size: 14, weight: .semibold))
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
                        .font(.system(size: 14, weight: .bold))
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
                .font(.system(size: 44))
                .foregroundStyle(Color.secondary.opacity(0.7))

            Text("لا تتوفر بيانات كافية")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.primary)

            Text("لم يتم تسجيل أي جرعات مجدولة للمستفيد خلال فترة \(currentPeriod.titleArabic) (\(currentPeriod.dateRangeString)).")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.dawaiGlassBorder, lineWidth: 1)
                )
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
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("الالتزام")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                // Tier badge and description
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(report.tier.titleArabic)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(report.tier.color)

                        Spacer()

                        if let trend = report.trendVsPreviousWeek {
                            trendPill(trend: trend)
                        }
                    }

                    Text(report.tier.messageArabic)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    Text("تم تناول \(report.totalTaken) من أصل \(report.totalScheduled) جرعة مجدولة")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.85))
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
                .font(.system(size: 10, weight: .bold))
            Text("\(isPositive ? "+" : "")\(Int(round(trend)))%")
                .font(.system(size: 11, weight: .bold))
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
        HStack(spacing: 8) {
            metricItem(title: "في الموعد", count: report.totalTakenOnTime, color: Color.dawaiTaken, icon: "checkmark.circle.fill")
            metricItem(title: "متأخرة", count: report.totalTakenLate, color: Color.dawaiWarning, icon: "clock.badge.exclamationmark.fill")
            metricItem(title: "فائتة", count: report.totalMissed, color: Color(red: 220.0 / 255.0, green: 53.0 / 255.0, blue: 69.0 / 255.0), icon: "xmark.circle.fill")
            metricItem(title: "الإجمالي", count: report.totalScheduled, color: Color.dawaiPrimary, icon: "pills.fill")
        }
    }

    @ViewBuilder
    private func metricItem(title: String, count: Int, color: Color, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)

            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
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
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("اضغط على أي يوم لعرض تفاصيل جرعاته")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.dawaiTaken)
                        .frame(width: 8, height: 8)
                    Text("الهدف 80%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // Interactive Weekly Bar Graph
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(report.dailySummaries) { day in
                    dayBarView(day: day)
                }
            }
            .frame(height: 140)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // Dotted 80% line explanation
            HStack {
                Text("المعدل الأسبوعي العام: \(Int(round(report.adherencePercentage)))%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(report.tier.color)

                Spacer()

                if selectedDayDate != nil {
                    Button {
                        withAnimation {
                            selectedDayDate = nil
                        }
                    } label: {
                        Text("عرض الأسبوع بالكامل")
                            .font(.system(size: 11, weight: .bold))
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
    private func dayBarView(day: DailyAdherenceSummary) -> some View {
        let isSelected = selectedDayDate != nil && Calendar.current.isDate(day.date, inSameDayAs: selectedDayDate!)
        let barHeight = day.isFuture ? 6.0 : max(8.0, CGFloat(day.percentage / 100.0) * 85.0)

        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if isSelected {
                    selectedDayDate = nil
                } else {
                    selectedDayDate = day.date
                }
            }
        } label: {
            VStack(spacing: 6) {
                // Top percentage label
                if !day.isFuture {
                    Text("\(Int(round(day.percentage)))%")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.dawaiPrimary : Color.secondary)
                } else {
                    Text("-")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                }

                Spacer(minLength: 0)

                // Bar capsule
                ZStack(alignment: .bottom) {
                    // Background track
                    Capsule()
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.6))
                        .frame(width: 22, height: 85)

                    // Filled value
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: dayBarColors(for: day),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 22, height: barHeight)
                }

                // Day name & indicator
                VStack(spacing: 2) {
                    Text(day.dayShortArabic)
                        .font(.system(size: 12, weight: isSelected || day.isToday ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.dawaiPrimary : (day.isToday ? Color.primary : Color.secondary))

                    if day.isToday {
                        Circle()
                            .fill(Color.dawaiPrimary)
                            .frame(width: 4, height: 4)
                    } else {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 4, height: 4)
                    }
                }
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

    private func dayBarColors(for day: DailyAdherenceSummary) -> [Color] {
        if day.isFuture {
            return [Color.secondary.opacity(0.2), Color.secondary.opacity(0.1)]
        } else if day.percentage >= 85.0 {
            return [Color.dawaiTaken, Color.dawaiTaken.opacity(0.8)]
        } else if day.percentage >= 50.0 {
            return [Color.dawaiWarning, Color.dawaiWarning.opacity(0.8)]
        } else {
            return [Color(red: 220.0 / 255.0, green: 53.0 / 255.0, blue: 69.0 / 255.0), Color.red.opacity(0.7)]
        }
    }

    // MARK: - 7. Medication Performance Breakdown
    @ViewBuilder
    private var medicationBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("الالتزام حسب كل دواء")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)

            VStack(spacing: 12) {
                ForEach(report.medicationSummaries) { med in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(med.name)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text(med.dosage)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(Int(round(med.percentage)))%")
                                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                                    .foregroundStyle(med.percentage >= 80 ? Color.dawaiTaken : Color.dawaiWarning)
                                Text("\(med.takenCount) من \(med.scheduledCount) جرعة")
                                    .font(.system(size: 11))
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
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                if let sel = selectedDayDate {
                    let f = DateFormatter()
                    let _ = f.locale = Locale.dawaiArabic
                    let _ = f.dateFormat = "EEEE d MMMM"
                    Text(f.string(from: sel).westernNumerals)
                        .font(.system(size: 12, weight: .semibold))
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
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("لا توجد سجلات جرعات لهذا اليوم")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(daysToDisplay) { day in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(day.dayNameArabic) • \(formatShortDate(day.date))")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.dawaiPrimary)

                                Spacer()

                                Text("\(day.takenCount)/\(day.scheduledCount) جرعة")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
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
                .font(.system(size: 18))
                .foregroundStyle(record.status.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.medicationName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)

                Text(record.dosage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(record.status.titleArabic)
                        .font(.system(size: 11, weight: .bold))
                    if record.delayMinutes > 0 && record.status == .takenLate {
                        Text("(\(record.delayMinutes) د تأخير)")
                            .font(.system(size: 10))
                    }
                }
                .foregroundStyle(record.status.color)

                Text(formatTime(record.scheduledDate))
                    .font(.system(size: 11))
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

    private func prepareShareText() {
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
        self.shareText = text
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
