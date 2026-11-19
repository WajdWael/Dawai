//
//  AdherenceService.swift
//  Dawai
//
//  Use-Case 7 (UC-7): View Adherence Report
//  Service coordinating dose log storage, week-period partitioning,
//  authorization validation, and weekly adherence calculations.
//

import Foundation
import Combine

@MainActor
public final class AdherenceService: ObservableObject {
    public static let shared = AdherenceService()

    @Published public private(set) var doseRecords: [DoseRecord] = []

    /// Persistence for the dose log (UserDefaults today, replaceable later).
    private let store: any DoseRecordStore
    private let relationshipService: RelationshipService
    private let calendar: Calendar

    public init(
        store: any DoseRecordStore = UserDefaultsDoseRecordStore(),
        relationshipService: RelationshipService? = nil
    ) {
        self.store = store
        self.relationshipService = relationshipService ?? .shared
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale.dawaiArabic
        cal.firstWeekday = 1 // Sunday as the start of the week in Arab region
        self.calendar = cal

        loadRecords()
    }

    // MARK: - Persistence
    public func loadRecords() {
        // A new user starts with no dose history.
        self.doseRecords = store.loadDoseRecords()
    }

    // MARK: - Reset (wipes all dose history on this device)
    public func resetAllData() {
        doseRecords = []
        store.removeAll()
    }

    // MARK: - Demo data (Loaded on request from Settings for testing)
    public func loadDemoHistory() {
        seedRealisticDoseHistory()
    }

    /// A record belongs to a patient only when the ids match.
    /// Demo history (Debug builds with demo mode on) is stored under "default_patient" and shown to everyone.
    private func record(_ record: DoseRecord, belongsTo patientId: String) -> Bool {
        if record.patientId == patientId { return true }
        return DemoModeService.shared.isActive && record.patientId == "default_patient"
    }

    private func persistRecords() {
        store.saveDoseRecords(doseRecords)
    }

    public func records(forPatient patientId: String) -> [DoseRecord] {
        doseRecords.filter { $0.patientId == patientId }
    }

    public func mergeImportedRecords(_ imported: [DoseRecord], forPatient patientId: String) {
        applyRemoteDoseRecords(imported, forPatient: patientId)
    }

    /// Merges dose records pulled from CloudKit or sync bundles without downgrading taken records to missed/upcoming.
    public func applyRemoteDoseRecords(_ imported: [DoseRecord], forPatient patientId: String) {
        guard !imported.isEmpty else { return }
        var changed = false
        for rec in imported where rec.patientId == patientId {
            if let existingIdx = doseRecords.firstIndex(where: {
                $0.id == rec.id ||
                ($0.medicationId == rec.medicationId &&
                 calendar.isDate($0.scheduledDate, inSameDayAs: rec.scheduledDate) &&
                 minuteOfDay(for: $0.scheduledDate) == minuteOfDay(for: rec.scheduledDate))
            }) {
                let existing = doseRecords[existingIdx]
                let existingTaken = existing.status == .takenOnTime || existing.status == .takenLate
                let incomingTaken = rec.status == .takenOnTime || rec.status == .takenLate
                if existingTaken && !incomingTaken {
                    continue
                }
                if existing != rec {
                    doseRecords[existingIdx] = rec
                    changed = true
                }
            } else {
                doseRecords.append(rec)
                changed = true
            }
        }
        if changed {
            persistRecords()
        }
    }

    // MARK: - UC-7 S#2: Permission & Authorization Verification
    public func verifyAccess(actor: UserIdentity, targetPatientId: String) -> (isAuthorized: Bool, errorReason: String?) {
        // Patients have direct access to their own reports
        if actor.role == .patient {
            if actor.id == targetPatientId || targetPatientId.isEmpty {
                return (true, nil)
            } else {
                return (false, "لا يملك المستفيد صلاحية الاطلاع على تقارير مستفيدين آخرين.")
            }
        }

        // Caregivers: verify active relationship permissions
        let activeRels = relationshipService.activeRelationships
        let hasActiveRelation = activeRels.contains { rel in
            rel.caregiverId == actor.id && rel.patientId == targetPatientId && rel.isActive
        }

        if hasActiveRelation {
            return (true, nil)
        }

        // Allow demo beneficiaries only while demo mode is on (Debug builds)
        if DemoModeService.shared.isDemoPatient(targetPatientId) {
            return (true, nil)
        }

        return (false, "لا تملك الصلاحية للاطلاع على تقرير هذا المستفيد. يرجى التأكد من قبول وتأكيد الارتباط.")
    }

    // MARK: - Dose Logging (Triggered by UC-6 Confirm Dose)
    private func minuteOfDay(for date: Date) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func matchesSlot(_ record: DoseRecord, medicationId: UUID, on dayDate: Date, slotMinutes: Int?) -> Bool {
        guard record.medicationId == medicationId,
              calendar.isDate(record.scheduledDate, inSameDayAs: dayDate) else {
            return false
        }
        guard let slotMinutes else { return true }
        return minuteOfDay(for: record.scheduledDate) == slotMinutes
    }

    public func hasRecord(for medicationId: UUID, on dayDate: Date, slotMinutes: Int? = nil) -> Bool {
        doseRecords.contains { rec in
            matchesSlot(rec, medicationId: medicationId, on: dayDate, slotMinutes: slotMinutes)
        }
    }

    public func hasTakenRecord(for medicationId: UUID, on dayDate: Date, slotMinutes: Int? = nil) -> Bool {
        doseRecords.contains { rec in
            matchesSlot(rec, medicationId: medicationId, on: dayDate, slotMinutes: slotMinutes) &&
            (rec.status == .takenOnTime || rec.status == .takenLate)
        }
    }

    public func recordDoseTaken(
        medication: MedicationItem,
        patientId: String,
        takenAt: Date? = nil,
        scheduledDay: Date? = nil,
        slotMinutes: Int? = nil
    ) {
        let effectiveTakenAt = takenAt ?? AppClock.shared.now
        let targetDay = calendar.startOfDay(for: scheduledDay ?? effectiveTakenAt)
        let resolvedSlot = slotMinutes ?? minuteOfDay(for: scheduledDateTime(for: medication, on: targetDay))

        let savedRecord: DoseRecord
        // Find existing record for this medication slot on targetDay, or create new one
        if let idx = doseRecords.firstIndex(where: {
            matchesSlot($0, medicationId: medication.id, on: targetDay, slotMinutes: resolvedSlot)
        }) {
            // Prevent duplicate confirmation if already marked as taken on targetDay
            if doseRecords[idx].status == .takenOnTime || doseRecords[idx].status == .takenLate {
                return
            }

            let sched = doseRecords[idx].scheduledDate
            let delayMinutes = max(0, Int(effectiveTakenAt.timeIntervalSince(sched) / 60))
            let isLate = delayMinutes >= DoseWindowConfig.lateThresholdMinutes

            doseRecords[idx].takenDate = effectiveTakenAt
            doseRecords[idx].status = isLate ? .takenLate : .takenOnTime
            doseRecords[idx].delayMinutes = delayMinutes
            savedRecord = doseRecords[idx]
        } else {
            // Create record
            let sched = scheduledDateTime(for: medication, on: targetDay, slotMinutes: resolvedSlot)
            let delayMinutes = max(0, Int(effectiveTakenAt.timeIntervalSince(sched) / 60))
            let isLate = delayMinutes >= DoseWindowConfig.lateThresholdMinutes

            let record = DoseRecord(
                patientId: patientId,
                medicationId: medication.id,
                medicationName: medication.name,
                dosage: medication.dosage,
                scheduledDate: sched,
                takenDate: effectiveTakenAt,
                status: isLate ? .takenLate : .takenOnTime,
                delayMinutes: delayMinutes
            )
            doseRecords.append(record)
            savedRecord = record
        }

        persistRecords()
        CloudKitSyncManager.shared.publishDoseRecord(savedRecord)
    }

    /// Marks a scheduled dose slot as `.missed` ("فائتة") in the adherence log once its late confirmation window has expired without being taken.
    public func recordDoseMissedIfNeeded(
        medication: MedicationItem,
        patientId: String,
        on date: Date? = nil,
        slotMinutes: Int? = nil
    ) {
        let dayStart = calendar.startOfDay(for: date ?? AppClock.shared.now)
        let resolvedSlot = slotMinutes ?? minuteOfDay(for: scheduledDateTime(for: medication, on: dayStart))
        if let idx = doseRecords.firstIndex(where: {
            matchesSlot($0, medicationId: medication.id, on: dayStart, slotMinutes: resolvedSlot)
        }) {
            if doseRecords[idx].status == .upcoming {
                doseRecords[idx].status = .missed
                doseRecords[idx].takenDate = nil
                doseRecords[idx].delayMinutes = 0
                persistRecords()
                CloudKitSyncManager.shared.publishDoseRecord(doseRecords[idx])
            }
            return
        }

        let sched = scheduledDateTime(for: medication, on: dayStart, slotMinutes: resolvedSlot)
        let record = DoseRecord(
            patientId: patientId,
            medicationId: medication.id,
            medicationName: medication.name,
            dosage: medication.dosage,
            scheduledDate: sched,
            takenDate: nil,
            status: .missed,
            delayMinutes: 0
        )
        doseRecords.append(record)
        persistRecords()
        CloudKitSyncManager.shared.publishDoseRecord(record)
    }

    // MARK: - UC-7 S#3: Available Week Periods
    public func availableWeekPeriods(count: Int = 4, referenceDate: Date? = nil) -> [WeekPeriod] {
        var periods: [WeekPeriod] = []

        // Compute start of current week (Sunday 00:00:00)
        let currentWeekStart = startOfWeek(for: referenceDate ?? AppClock.shared.now)

        for offset in 0..<count {
            guard let weekStart = calendar.date(byAdding: .day, value: -(offset * 7), to: currentWeekStart),
                  let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart),
                  let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: weekEnd) else {
                continue
            }

            let title: String
            switch offset {
            case 0:
                title = "هذا الأسبوع"
            case 1:
                title = "الأسبوع الماضي"
            case 2:
                title = "قبل أسبوعين"
            case 3:
                title = "قبل 3 أسابيع"
            default:
                title = "قبل \(offset) أسابيع"
            }

            let rangeStr = formatWeekDateRange(start: weekStart, end: weekEnd)
            let period = WeekPeriod(
                id: -offset,
                startDate: weekStart,
                endDate: endOfDay,
                titleArabic: title,
                dateRangeString: rangeStr
            )
            periods.append(period)
        }

        return periods
    }

    // MARK: - UC-7 S#4 & S#5: Generate Weekly Adherence Report
    public func generateWeeklyReport(
        patientId: String,
        patientDisplayName: String,
        period: WeekPeriod
    ) -> WeeklyAdherenceReport {
        // 1. Gather all records for target patient in this week period
        let patientRecords = doseRecords.filter { rec in
            record(rec, belongsTo: patientId) &&
            rec.scheduledDate >= period.startDate &&
            rec.scheduledDate <= period.endDate
        }

        // Check if sufficient data is available (Post-condition requirement)
        let totalScheduled = patientRecords.count
        guard totalScheduled > 0 else {
            return WeeklyAdherenceReport(
                patientId: patientId,
                patientDisplayName: patientDisplayName,
                period: period,
                totalScheduled: 0,
                totalTaken: 0,
                totalTakenOnTime: 0,
                totalTakenLate: 0,
                totalMissed: 0,
                adherencePercentage: 0.0,
                dailySummaries: [],
                medicationSummaries: [],
                hasSufficientData: false,
                trendVsPreviousWeek: nil
            )
        }

        // 2. Count statuses
        let takenOnTime = patientRecords.filter { $0.status == .takenOnTime }.count
        let takenLate = patientRecords.filter { $0.status == .takenLate }.count
        let totalTaken = takenOnTime + takenLate
        let totalMissed = patientRecords.filter { $0.status == .missed }.count

        // 3. Adherence percentage calculation: (totalTaken / totalScheduled) * 100
        let percentage = (Double(totalTaken) / Double(totalScheduled)) * 100.0

        // 4. Generate 7 Daily Summaries (Sunday through Saturday)
        var dailySummaries: [DailyAdherenceSummary] = []
        let today = calendar.startOfDay(for: AppClock.shared.now)

        for dayOffset in 0..<7 {
            guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: period.startDate) else {
                continue
            }
            let isDayToday = calendar.isDate(dayDate, inSameDayAs: today)
            let isDayFuture = dayDate > today

            let dayRecords = patientRecords.filter { calendar.isDate($0.scheduledDate, inSameDayAs: dayDate) }
            let daySched = dayRecords.count
            let dayOnTime = dayRecords.filter { $0.status == .takenOnTime }.count
            let dayLate = dayRecords.filter { $0.status == .takenLate }.count
            let dayTaken = dayOnTime + dayLate
            let dayMissed = dayRecords.filter { $0.status == .missed }.count
            let dayPct = daySched > 0 ? (Double(dayTaken) / Double(daySched)) * 100.0 : 0.0

            let dayNameArabic = dayName(for: dayDate)
            let shortDayArabic = shortDayName(for: dayDate)

            dailySummaries.append(
                DailyAdherenceSummary(
                    date: dayDate,
                    dayNameArabic: dayNameArabic,
                    dayShortArabic: shortDayArabic,
                    isToday: isDayToday,
                    isFuture: isDayFuture,
                    scheduledCount: daySched,
                    takenCount: dayTaken,
                    takenOnTimeCount: dayOnTime,
                    takenLateCount: dayLate,
                    missedCount: dayMissed,
                    percentage: dayPct,
                    records: dayRecords.sorted(by: { $0.scheduledDate < $1.scheduledDate })
                )
            )
        }

        // 5. Medication-specific summaries
        var medMap: [UUID: [DoseRecord]] = [:]
        for record in patientRecords {
            medMap[record.medicationId, default: []].append(record)
        }

        var medSummaries: [MedicationAdherenceSummary] = []
        for (medId, records) in medMap {
            let name = records.first?.medicationName ?? "دواء"
            let dosage = records.first?.dosage ?? ""
            let sched = records.count
            let taken = records.filter { $0.status == .takenOnTime || $0.status == .takenLate }.count
            let missed = records.filter { $0.status == .missed }.count
            let pct = sched > 0 ? (Double(taken) / Double(sched)) * 100.0 : 0.0

            medSummaries.append(
                MedicationAdherenceSummary(
                    medicationId: medId,
                    name: name,
                    dosage: dosage,
                    scheduledCount: sched,
                    takenCount: taken,
                    missedCount: missed,
                    percentage: pct
                )
            )
        }
        medSummaries.sort { $0.percentage > $1.percentage }

        // 6. Trend comparison vs previous week
        var trendVsPrev: Double? = nil
        if let prevStart = calendar.date(byAdding: .day, value: -7, to: period.startDate),
           let prevEnd = calendar.date(byAdding: .second, value: -1, to: period.startDate) {
            let prevRecords = doseRecords.filter { rec in
                record(rec, belongsTo: patientId) &&
                rec.scheduledDate >= prevStart &&
                rec.scheduledDate <= prevEnd
            }
            if !prevRecords.isEmpty {
                let prevTaken = prevRecords.filter { $0.status == .takenOnTime || $0.status == .takenLate }.count
                let prevPct = (Double(prevTaken) / Double(prevRecords.count)) * 100.0
                trendVsPrev = percentage - prevPct
            }
        }

        return WeeklyAdherenceReport(
            patientId: patientId,
            patientDisplayName: patientDisplayName,
            period: period,
            totalScheduled: totalScheduled,
            totalTaken: totalTaken,
            totalTakenOnTime: takenOnTime,
            totalTakenLate: takenLate,
            totalMissed: totalMissed,
            adherencePercentage: percentage,
            dailySummaries: dailySummaries,
            medicationSummaries: medSummaries,
            hasSufficientData: true,
            trendVsPreviousWeek: trendVsPrev
        )
    }

    // MARK: - Date Helpers
    private func startOfWeek(for date: Date) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
    }

    private func formatWeekDateRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.dawaiArabic
        formatter.dateFormat = "d MMMM"
        let startStr = formatter.string(from: start).westernNumerals
        let endStr = formatter.string(from: end).westernNumerals

        let yearFormatter = DateFormatter()
        yearFormatter.locale = Locale.dawaiArabic
        yearFormatter.dateFormat = "yyyy"
        let yearStr = yearFormatter.string(from: end).westernNumerals

        return "\(startStr) - \(endStr) \(yearStr)"
    }

    private func dayName(for date: Date) -> String {
        let weekday = calendar.component(.weekday, from: date)
        switch weekday {
        case 1: return "الأحد"
        case 2: return "الاثنين"
        case 3: return "الثلاثاء"
        case 4: return "الأربعاء"
        case 5: return "الخميس"
        case 6: return "الجمعة"
        case 7: return "السبت"
        default: return ""
        }
    }

    private func shortDayName(for date: Date) -> String {
        let weekday = calendar.component(.weekday, from: date)
        switch weekday {
        case 1: return "أحد"
        case 2: return "اثنين"
        case 3: return "ثلاثاء"
        case 4: return "أربعاء"
        case 5: return "خميس"
        case 6: return "جمعة"
        case 7: return "سبت"
        default: return ""
        }
    }

    private func scheduledDateTime(for med: MedicationItem, on dayDate: Date, slotMinutes: Int? = nil) -> Date {
        let minutes: Int
        if let slotMinutes {
            minutes = slotMinutes
        } else if let date = med.scheduledDate {
            let comps = calendar.dateComponents([.hour, .minute], from: date)
            minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        } else {
            minutes = parseTimeToMinutes(med.timeString)
        }
        let hour = minutes / 60
        let minute = minutes % 60
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayDate) ?? dayDate
    }

    private func parseTimeToMinutes(_ timeStr: String) -> Int {
        let clean = timeStr.westernNumerals.trimmingCharacters(in: .whitespaces)
        let isPM = clean.contains("م") || clean.lowercased().contains("pm")
        let isAM = clean.contains("ص") || clean.lowercased().contains("am")

        let digits = clean.replacingOccurrences(of: "[^0-9:]", with: "", options: .regularExpression)
        let parts = digits.split(separator: ":")
        guard let hStr = parts.first, let h = Int(hStr) else { return 12 * 60 }
        let m = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0

        var hour = h
        if isPM && hour < 12 {
            hour += 12
        } else if isAM && hour == 12 {
            hour = 0
        }
        return hour * 60 + m
    }

    #if DEBUG
    // MARK: - Realistic Dose History Seeding (Past 4 Weeks, Debug demo data only)
    private func seedRealisticDoseHistory() {
        var seeded: [DoseRecord] = []
        let today = calendar.startOfDay(for: Date())
        let weekStart = startOfWeek(for: today)

        // Medications to seed
        let med1 = (UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, "اسبرين", "حبتان قبل الاكل", 8 * 60) // 8:00 AM
        let med2 = (UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, "ميترفين", "حبة واحدة بعد الأكل", 13 * 60) // 1:00 PM
        let med3 = (UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, "فيتامين د", "قطرة واحدة يوميًا", 20 * 60) // 8:00 PM

        let patientIds = ["default_patient", "cg_patient_omar", "cg_patient_kholoud"]

        for pid in patientIds {
            // Seed across 28 days (4 weeks: current week + 3 previous weeks)
            for dayOffset in -21...6 {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
                let isTodayDay = calendar.isDate(day, inSameDayAs: today)
                let isFutureDay = day > today

                // If future, don't seed taken records for days beyond today
                if isFutureDay { continue }

                let meds = [med1, med2, med3]
                for (idx, med) in meds.enumerated() {
                    let schedTime = calendar.date(bySettingHour: med.3 / 60, minute: med.3 % 60, second: 0, of: day) ?? day

                    let status: DoseStatus
                    let takenDate: Date?
                    let delayMinutes: Int

                    if isTodayDay {
                        // For today: first dose taken, second late, third upcoming
                        if idx == 0 {
                            status = .takenOnTime
                            delayMinutes = 4
                            takenDate = calendar.date(byAdding: .minute, value: 4, to: schedTime)
                        } else if idx == 1 {
                            status = .takenLate
                            delayMinutes = 35
                            takenDate = calendar.date(byAdding: .minute, value: 35, to: schedTime)
                        } else {
                            status = .upcoming
                            delayMinutes = 0
                            takenDate = nil
                        }
                    } else {
                        // Past days realistic pattern (approx 90% adherence)
                        let rand = (dayOffset * 7 + idx * 13 + pid.count * 5) % 100
                        if rand < 78 {
                            status = .takenOnTime
                            delayMinutes = rand % 15
                            takenDate = calendar.date(byAdding: .minute, value: delayMinutes, to: schedTime)
                        } else if rand < 90 {
                            status = .takenLate
                            delayMinutes = 30 + (rand % 40)
                            takenDate = calendar.date(byAdding: .minute, value: delayMinutes, to: schedTime)
                        } else {
                            status = .missed
                            delayMinutes = 0
                            takenDate = nil
                        }
                    }

                    seeded.append(
                        DoseRecord(
                            patientId: pid,
                            medicationId: med.0,
                            medicationName: med.1,
                            dosage: med.2,
                            scheduledDate: schedTime,
                            takenDate: takenDate,
                            status: status,
                            delayMinutes: delayMinutes
                        )
                    )
                }
            }
        }

        self.doseRecords = seeded
        persistRecords()
    }
    #endif
}
