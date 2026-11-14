//
//  MedicationService.swift
//  Dawai
//
//  Use-Case 3 (UC-3): Add Medication
//  Service managing medication lifecycle, input validation, persistence,
//  authorization checks, and local reminder notification scheduling.
//

import Foundation
import Combine
import SwiftUI
import UserNotifications

@MainActor
public final class MedicationService: ObservableObject {
    public static let shared = MedicationService()

    // MARK: - Published State
    /// Every medication stored on this device, for all patients. Screens should not list this directly:
    /// use `medications` (the patient using this device) or `medicationList(forPatient:)` / `daySchedule(forPatient:)`.
    @Published public private(set) var allMedications: [MedicationItem] = []
    /// Medications owned by the patient using this device (`currentPatientId`).
    @Published public private(set) var medications: [MedicationItem] = []
    /// Patient whose schedule drives `medications`, `todayMedications`, `activeMedication`, `upcomingDoses` and `remainingDoses`.
    @Published public private(set) var currentPatientId: String = MedicationItem.fallbackPatientId
    @Published public var activeMedication: MedicationItem?
    @Published public var upcomingDoses: [UpcomingDose] = []
    /// Untaken doses scheduled for today. Always derived from the real schedule in `refreshDerivedState()`.
    @Published public var remainingDoses: Int = 0

    // MARK: - Use-Case 12 (UC-12): Today's Medications & Auto-Sorting State
    @Published public private(set) var todayMedications: [MedicationItem] = []
    private var timeProgressionTimer: AnyCancellable?

    // MARK: - Use-Case 11 (UC-11): Collaborative Medication Deletion State
    @Published public private(set) var pendingDeletionRequests: [MedicationDeletionRequest] = []

    // Feedback & Toast notifications
    @Published public var toastMessage: String? = nil
    @Published public var notificationWarning: String? = nil

    /// Persistence for medications and deletion requests (UserDefaults today, replaceable later).
    private let store: any MedicationStore
    private let maxImageSizeBytes = 5 * 1024 * 1024 // 5 MB (UC-3 S#4)

    public static let doseReminderCategoryIdentifier = "DAWAI_DOSE_REMINDER_CATEGORY"
    public static let confirmDoseActionIdentifier = "DAWAI_CONFIRM_DOSE_ACTION"

    public init(store: any MedicationStore = UserDefaultsMedicationStore()) {
        self.store = store
        registerNotificationCategories()
        loadPersistedMedications()
        loadPersistedDeletionRequests()
        setupTimeProgressionTimer()
    }

    private func registerNotificationCategories() {
        let confirmAction = UNNotificationAction(
            identifier: Self.confirmDoseActionIdentifier,
            title: "أخذت الدواء",
            options: [.authenticationRequired]
        )
        let category = UNNotificationCategory(
            identifier: Self.doseReminderCategoryIdentifier,
            actions: [confirmAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - UC-12 S#3: Time Progresses (Auto-updates schedule as time passes)
    private func setupTimeProgressionTimer() {
        timeProgressionTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshDerivedState()
            }
    }

    // MARK: - Persistence & Initial State
    public func loadPersistedMedications() {
        let identity = KeychainService.shared.loadUserIdentity()
        // Items saved before `patientId` existed are assigned to the identity using this device.
        // A new user starts with no medications.
        let stored = store.loadMedications(legacyPatientId: identity?.id ?? MedicationItem.fallbackPatientId)
        self.allMedications = stored.map { item in
            var m = item
            m.timeString = m.timeString.westernNumerals
            m.dosage = m.dosage.westernNumerals
            return m
        }
        reassignLegacyCaregiverMedications(identity: identity)
        refreshDerivedState()
    }

    /// A caregiver never owns medications. Legacy items on a caregiver's device were assigned to the caregiver's
    /// own id when decoded; when exactly one patient is linked, they can only belong to that patient.
    private func reassignLegacyCaregiverMedications(identity: UserIdentity?) {
        guard let identity, identity.role == .caregiver else { return }
        let linkedPatientIds = Set(
            RelationshipService.shared.activeRelationships
                .filter { $0.caregiverId == identity.id && $0.isActive }
                .map(\.patientId)
        )
        guard linkedPatientIds.count == 1, let patientId = linkedPatientIds.first else { return }

        var changed = false
        for idx in allMedications.indices where allMedications[idx].patientId == identity.id {
            allMedications[idx].patientId = patientId
            changed = true
        }
        if changed {
            persistMedications()
        }
    }

    /// Medications owned by `patientId`.
    public func medicationList(forPatient patientId: String) -> [MedicationItem] {
        allMedications.filter { $0.patientId == patientId }
    }

    // MARK: - Reset (wipes all medication data on this device)
    public func resetAllData() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        allMedications = []
        pendingDeletionRequests = []
        toastMessage = nil
        notificationWarning = nil

        store.removeAll()
        refreshDerivedState()
    }

    #if DEBUG
    // MARK: - Demo data (Debug builds only, loaded on request from Settings)
    public func loadDemoData() {
        // A patient owns the demo medications; on a caregiver's device they belong to the demo beneficiaries.
        let identity = KeychainService.shared.loadUserIdentity()
        let owner = identity?.role == .patient ? (identity?.id ?? MedicationItem.fallbackPatientId) : MedicationItem.fallbackPatientId
        var demoAspirin = HomeMockData.activeMedication
        demoAspirin.patientId = owner
        allMedications = [
            demoAspirin,
            MedicationItem(patientId: owner, name: "ميترفين", dosage: "حبة واحدة بعد الأكل", timeString: "12:00 ص", scheduledDate: nil, days: ["كل يوم"], frequency: "مرة يوميًا"),
            MedicationItem(patientId: owner, name: "فيتامين د", dosage: "قطرة واحدة يوميًا", timeString: "10:00 ص", scheduledDate: nil, days: ["كل يوم"], frequency: "مرة يوميًا")
        ]
        persistMedications()
        refreshDerivedState()
    }
    #endif

    private func persistMedications() {
        store.saveMedications(allMedications)
    }

    // MARK: - UC-11 Deletion Requests Persistence
    public func loadPersistedDeletionRequests() {
        self.pendingDeletionRequests = store.loadDeletionRequests()
    }

    private func persistDeletionRequests() {
        store.saveDeletionRequests(pendingDeletionRequests)
    }

    // MARK: - Dose Time Window Rules (Backed by DoseWindowConfig)
    public static var preDoseWindowMinutes: Int { DoseWindowConfig.preWindowMinutes }
    public static var lateThresholdMinutes: Int { DoseWindowConfig.lateThresholdMinutes }
    public static var missedCutoffMinutes: Int { DoseWindowConfig.missedCutoffMinutes }

    public enum DoseInteractionState: Equatable {
        case taken
        case upcomingBeforeWindow
        case dueOnTime
        case overdueLate
        case missed
    }

    /// Computes the exact scheduled `Date` for `item` on the calendar day of `dayDate`.
    public func scheduledDateTime(for item: MedicationItem, on dayDate: Date) -> Date {
        let calendar = Calendar.current
        let mins = scheduledMinutes(for: item)
        return calendar.date(bySettingHour: mins / 60, minute: mins % 60, second: 0, of: dayDate) ?? dayDate
    }

    /// Returns true when yesterday's scheduled dose was not yet recorded and its confirmation window extends past midnight into `date`.
    private func hasActiveCarryoverFromYesterday(_ item: MedicationItem, at date: Date) -> Bool {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date),
              isScheduledForToday(item, on: yesterday) else {
            return false
        }
        let yesterdaySched = scheduledDateTime(for: item, on: yesterday)
        let createdMinuteStart = calendar.date(bySetting: .second, value: 0, of: item.createdAt) ?? item.createdAt
        if calendar.isDate(yesterday, inSameDayAs: item.createdAt) && yesterdaySched < createdMinuteStart {
            return false
        }
        guard !AdherenceService.shared.hasRecord(for: item.id, on: yesterday) else {
            return false
        }
        let diffYesterdayMin = Int(floor(date.timeIntervalSince(yesterdaySched) / 60.0))
        return diffYesterdayMin >= -DoseWindowConfig.preWindowMinutes && diffYesterdayMin < DoseWindowConfig.missedCutoffMinutes
    }

    /// Returns the active occurrence `Date` (yesterday carryover if still open past midnight, otherwise today's scheduled `Date`).
    private func activeOccurrenceDate(for item: MedicationItem, at date: Date) -> Date {
        if hasActiveCarryoverFromYesterday(item, at: date),
           let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) {
            return scheduledDateTime(for: item, on: yesterday)
        }
        return scheduledDateTime(for: item, on: date)
    }

    /// Evaluates the current interaction state of a scheduled medication for today (including midnight carryover from yesterday)
    public func doseInteractionState(for item: MedicationItem, at date: Date? = nil) -> DoseInteractionState {
        let effectiveDate = date ?? AppClock.shared.now
        let calendar = Calendar.current

        if item.isTaken {
            if let takenAt = item.takenAt {
                if calendar.isDate(takenAt, inSameDayAs: effectiveDate) {
                    return .taken
                }
            } else {
                return .taken
            }
        }

        // Check if yesterday's dose crossed midnight and is still within the active confirmation window
        if hasActiveCarryoverFromYesterday(item, at: effectiveDate),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: effectiveDate) {
            let yesterdaySched = scheduledDateTime(for: item, on: yesterday)
            let diffYesterdayMin = Int(floor(effectiveDate.timeIntervalSince(yesterdaySched) / 60.0))
            return diffYesterdayMin <= DoseWindowConfig.lateThresholdMinutes ? .dueOnTime : .overdueLate
        }

        guard isScheduledForToday(item, on: effectiveDate) else {
            return .upcomingBeforeWindow
        }

        let todaySched = scheduledDateTime(for: item, on: effectiveDate)
        let diffMin = Int(floor(effectiveDate.timeIntervalSince(todaySched) / 60.0))

        if diffMin < -DoseWindowConfig.preWindowMinutes {
            return .upcomingBeforeWindow
        } else if diffMin <= DoseWindowConfig.lateThresholdMinutes {
            return .dueOnTime
        } else if diffMin < DoseWindowConfig.missedCutoffMinutes {
            return .overdueLate
        } else {
            return .missed
        }
    }

    /// Reconciles taken flags from previous days, handles doses crossing midnight without losing their state,
    /// and retroactively marks any past unrecorded scheduled doses whose cutoff window has elapsed as `.missed`.
    /// Every dose record is written under the medication's own `patientId`.
    private func reconcilePastAndMidnightDoses(at now: Date) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)

        // 1. Preserve previous-day `isTaken` state in AdherenceService BEFORE resetting `isTaken` for the new day
        var didResetStaleDay = false
        var resetMedications: [MedicationItem] = []
        for idx in allMedications.indices {
            if allMedications[idx].isTaken,
               let takenAt = allMedications[idx].takenAt,
               !calendar.isDate(takenAt, inSameDayAs: now) {
                AdherenceService.shared.recordDoseTaken(
                    medication: allMedications[idx],
                    patientId: allMedications[idx].patientId,
                    takenAt: takenAt,
                    scheduledDay: takenAt
                )
                allMedications[idx].isTaken = false
                allMedications[idx].takenAt = nil
                didResetStaleDay = true
                resetMedications.append(allMedications[idx])
            }
        }
        if didResetStaleDay {
            persistMedications()
            // Confirming yesterday's dose removed the repeating missed-dose alert (`cancelMissedDoseAlert`).
            // The dose is open again today, so the alert must be scheduled again.
            let toReschedule = resetMedications
            Task {
                for med in toReschedule {
                    await self.scheduleMissedDoseAlert(for: med)
                }
            }
        }

        // 2. Retroactive backfill for past days (only when the confirmation window has fully expired)
        for med in allMedications {
            let createdDay = calendar.startOfDay(for: med.createdAt)
            let earliestLookback = calendar.date(byAdding: .day, value: -DoseWindowConfig.retroactiveLookbackDays, to: todayStart) ?? createdDay
            var day = max(createdDay, earliestLookback)
            let createdMinuteStart = calendar.date(bySetting: .second, value: 0, of: med.createdAt) ?? med.createdAt

            while day < todayStart {
                if isScheduledForToday(med, on: day) {
                    let schedDate = scheduledDateTime(for: med, on: day)
                    let isBeforeCreation = calendar.isDate(day, inSameDayAs: med.createdAt) && schedDate < createdMinuteStart
                    if !isBeforeCreation {
                        let elapsedMinutes = Int(floor(now.timeIntervalSince(schedDate) / 60.0))
                        // If a midnight-crossing dose (e.g. 23:00 checked at 00:30) is still within 120m, keep it open rather than marking missed
                        if elapsedMinutes >= DoseWindowConfig.missedCutoffMinutes && !AdherenceService.shared.hasRecord(for: med.id, on: day) {
                            AdherenceService.shared.recordDoseMissedIfNeeded(
                                medication: med,
                                patientId: med.patientId,
                                on: day
                            )
                        }
                    }
                }
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
            }
        }
    }

    // MARK: - Per-Patient Day Schedule
    /// Today's schedule for one patient, derived only from that patient's medications.
    public struct PatientDaySchedule: Equatable {
        public let patientId: String
        /// Medications scheduled today (or still open from yesterday past midnight), sorted chronologically.
        public let todayMedications: [MedicationItem]
        public let activeMedication: MedicationItem?
        public let upcomingDoses: [UpcomingDose]
        /// Untaken doses that can still be confirmed today (excludes taken and missed doses).
        public let remainingDoses: Int
        /// Today's doses still unconfirmed past `DoseWindowConfig.lateThresholdMinutes`.
        public let missedMedications: [MedicationItem]

        public var hasMissedDoses: Bool { !missedMedications.isEmpty }
    }

    /// UC-12 S#1, S#2, S#3: computes `patientId`'s schedule for the day containing `date`. Has no side effects.
    public func daySchedule(forPatient patientId: String, at date: Date? = nil) -> PatientDaySchedule {
        let now = date ?? AppClock.shared.now

        // 1. UC-12 S#1: Retrieve registered medications scheduled for today OR still active from yesterday past midnight
        let todaysList = allMedications.filter {
            $0.patientId == patientId &&
            (isScheduledForToday($0, on: now) || hasActiveCarryoverFromYesterday($0, at: now))
        }

        // 2. UC-12 S#2: Automatically sort daily medications chronologically by active occurrence date
        let sortedTodaysList = todaysList.sorted { a, b in
            activeOccurrenceDate(for: a, at: now) < activeOccurrenceDate(for: b, at: now)
        }

        // 3. UC-12 S#2: Prioritize confirmable or upcoming medications (excluding taken and missed doses)
        let actionableUntaken = sortedTodaysList.filter { item in
            let state = doseInteractionState(for: item, at: now)
            return state == .dueOnTime || state == .overdueLate || state == .upcomingBeforeWindow
        }

        let active: MedicationItem?
        if !actionableUntaken.isEmpty {
            let confirmableNow = actionableUntaken.filter { item in
                let state = doseInteractionState(for: item, at: now)
                return state == .dueOnTime || state == .overdueLate
            }
            let futureToday = actionableUntaken.filter { item in
                doseInteractionState(for: item, at: now) == .upcomingBeforeWindow
            }

            if !confirmableNow.isEmpty {
                // Prioritize the confirmable dose (within -15m ..< +120m window) closest to `now`
                active = confirmableNow.min(by: {
                    abs(now.timeIntervalSince(activeOccurrenceDate(for: $0, at: now))) <
                    abs(now.timeIntervalSince(activeOccurrenceDate(for: $1, at: now)))
                }) ?? confirmableNow.first
            } else {
                // All remaining actionable doses are in the future today; pick the earliest upcoming one
                active = futureToday.min(by: {
                    activeOccurrenceDate(for: $0, at: now) < activeOccurrenceDate(for: $1, at: now)
                }) ?? actionableUntaken.first
            }
        } else {
            // All doses for today are either taken or missed: show the most recent or first in schedule
            active = sortedTodaysList.last ?? sortedTodaysList.first
        }

        // 4. Generate schedule doses for other medications (excluding the active highlighted card)
        let upcoming = sortedTodaysList
            .filter { $0.id != active?.id }
            .map { item in
                UpcomingDose(
                    id: item.id,
                    name: item.name,
                    timeString: item.timeString.westernNumerals,
                    dosage: item.dosage.westernNumerals,
                    isTaken: item.isTaken
                )
            }

        return PatientDaySchedule(
            patientId: patientId,
            todayMedications: sortedTodaysList,
            activeMedication: active,
            upcomingDoses: upcoming,
            // 5. Count remaining actionable untaken doses for today (excludes taken and missed doses)
            remainingDoses: actionableUntaken.count,
            missedMedications: sortedTodaysList.filter { isDoseMissed($0, at: now) }
        )
    }

    // MARK: - UC-12 S#1, S#2, S#3: Automatically Sort & Prioritize by Scheduled Time
    public func refreshDerivedState() {
        let now = AppClock.shared.now
        let calendar = Calendar.current
        let patientId = MedicationItem.currentIdentityPatientId

        // Reconcile day rollover, midnight carryover, and past unrecorded missed doses before evaluating today
        reconcilePastAndMidnightDoses(at: now)

        // Automatically record any dose today that crossed the missed cutoff as `.missed` ("فائتة") in AdherenceService,
        // for every patient whose medications are stored on this device.
        let createdTodayCutoffCheck = { (item: MedicationItem) -> Bool in
            let createdMinuteStart = calendar.date(bySetting: .second, value: 0, of: item.createdAt) ?? item.createdAt
            let schedToday = self.scheduledDateTime(for: item, on: now)
            return schedToday >= createdMinuteStart || !calendar.isDate(item.createdAt, inSameDayAs: now)
        }
        for item in allMedications
        where (isScheduledForToday(item, on: now) || hasActiveCarryoverFromYesterday(item, at: now))
            && doseInteractionState(for: item, at: now) == .missed
            && createdTodayCutoffCheck(item) {
            AdherenceService.shared.recordDoseMissedIfNeeded(
                medication: item,
                patientId: item.patientId,
                on: now
            )
        }

        // Published state describes only the patient using this device
        let schedule = daySchedule(forPatient: patientId, at: now)
        self.currentPatientId = patientId
        self.medications = medicationList(forPatient: patientId)
        self.todayMedications = schedule.todayMedications
        self.activeMedication = schedule.activeMedication
        self.upcomingDoses = schedule.upcomingDoses
        self.remainingDoses = schedule.remainingDoses
    }

    // MARK: - Use-Case 5 (UC-5): Missed Dose Calculations (30-Minute Grace Period)
    /// UC-5 S#1: Determines if a scheduled dose has remained unconfirmed past `DoseWindowConfig.lateThresholdMinutes`
    public func isDoseMissed(_ item: MedicationItem, at date: Date? = nil) -> Bool {
        let effectiveDate = date ?? AppClock.shared.now
        let state = doseInteractionState(for: item, at: effectiveDate)
        return state == .overdueLate || state == .missed
    }

    /// The current patient's medications scheduled for today whose late threshold has passed without confirmation
    public var missedMedicationsToday: [MedicationItem] {
        let now = AppClock.shared.now
        return todayMedications.filter { isDoseMissed($0, at: now) }
    }

    /// True when any of the current patient's medications has remained unconfirmed 30 minutes past its due time
    public var hasMissedDosesToday: Bool {
        !missedMedicationsToday.isEmpty
    }

    // MARK: - UC-12 Helper Functions (Schedule Day & Time Calculations)
    /// UC-12 S#1: Identifies medications scheduled for the current day
    public func isScheduledForToday(_ item: MedicationItem, on date: Date = Date()) -> Bool {
        if item.days.isEmpty || item.days.contains("كل يوم") || item.days.contains("يومياً") || item.days.contains("دائم") {
            return true
        }

        let weekday = Calendar.current.component(.weekday, from: date)
        // 1: Sunday, 2: Monday, 3: Tuesday, 4: Wednesday, 5: Thursday, 6: Friday, 7: Saturday
        let weekdayKeywords: [Int: [String]] = [
            1: ["الاحد", "الأحد"],
            2: ["الاثنين", "الإثنين"],
            3: ["الثلاثاء"],
            4: ["الاربعاء", "الأربعاء"],
            5: ["الخميس"],
            6: ["الجمعه", "الجمعة"],
            7: ["السبت"]
        ]

        guard let keywords = weekdayKeywords[weekday] else { return true }
        return item.days.contains { day in
            keywords.contains { keyword in day.contains(keyword) }
        }
    }

    /// Converts scheduled time into minutes from midnight (0 ..< 1440) for precise chronological sorting
    public func scheduledMinutes(for item: MedicationItem) -> Int {
        if let date = item.scheduledDate {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }
        return parseTimeToMinutes(item.timeString)
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

    // MARK: - UC-3 S#2 & S#4: Add Medication
    public func addMedication(
        item: MedicationItem,
        currentUser: UserIdentity,
        targetPatientId: String? = nil
    ) async throws {
        var cleanItem = item
        cleanItem.timeString = cleanItem.timeString.westernNumerals
        cleanItem.dosage = cleanItem.dosage.westernNumerals

        // 1. Validation: Required fields (UC-3 Alternate Course S#1)
        try validateRequiredFields(name: cleanItem.name, dosage: cleanItem.dosage, timeString: cleanItem.timeString)

        // 2. Validation: Image size (UC-3 Alternate Course S#4)
        if let imgData = cleanItem.imageData {
            try validateImageData(imgData)
        }

        // 3. Authorization check for Caregiver (UC-3 Alternate Course S#8) and ownership:
        // a caregiver adds to a linked patient's schedule, a patient adds to their own.
        if currentUser.role == .caregiver {
            try validateCaregiverPermission(caregiverId: currentUser.id, targetPatientId: targetPatientId)
            guard let targetPatientId else { throw MedicationError.unauthorizedCaregiver }
            cleanItem.patientId = targetPatientId
        } else {
            cleanItem.patientId = currentUser.id
        }

        // 4. Prevent duplicate medication record with same name and time for the same patient
        let duplicate = allMedications.contains { existing in
            existing.patientId == cleanItem.patientId &&
            existing.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ==
                cleanItem.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() &&
            existing.timeString == cleanItem.timeString
        }
        if duplicate {
            // Avoid duplicate additions
            showToast("الدواء مسجل بالفعل بنفس الموعد.")
            return
        }

        // 5. Save to database / local store (UC-3 S#5)
        allMedications.insert(cleanItem, at: 0)
        persistMedications()
        refreshDerivedState()

        // 6. Schedule Notification Reminder (UC-3 S#6 & Alternate Course S#9)
        let scheduled = await scheduleReminder(for: cleanItem)
        if !scheduled {
            self.notificationWarning = "تم حفظ الدواء بنجاح، ولكن تعذر تفعيل التذكيرات (يرجى التحقق من أذونات الإشعارات في الإعدادات)."
        }

        // 7. Success confirmation message (UC-3 S#8)
        if currentUser.role == .caregiver {
            showToast("تمت إضافة دواء \"\(cleanItem.name)\" بنجاح في جدول المستفيد!")
        } else if !RelationshipService.shared.activeRelationships.isEmpty {
            showToast("تمت إضافة دواء \"\(cleanItem.name)\" بنجاح وجدولة التذكيرات!")
            // Instantly notify caregiver
            RelationshipService.shared.showToast("🔔 قام \(currentUser.displayName) بإضافة دواء جديد: \"\(cleanItem.name)\" (\(cleanItem.timeString))")
        } else {
            showToast("تمت إضافة دواء \"\(cleanItem.name)\" بنجاح وجدولة التذكيرات!")
        }
    }

    // MARK: - Update Existing Medication (Edit Mode)
    public func updateMedication(
        item: MedicationItem,
        currentUser: UserIdentity? = nil,
        targetPatientId: String? = nil
    ) async throws {
        var cleanItem = item
        cleanItem.timeString = cleanItem.timeString.westernNumerals
        cleanItem.dosage = cleanItem.dosage.westernNumerals

        // 1. Validation
        try validateRequiredFields(name: cleanItem.name, dosage: cleanItem.dosage, timeString: cleanItem.timeString)

        if let imgData = cleanItem.imageData {
            try validateImageData(imgData)
        }

        guard let index = allMedications.firstIndex(where: { $0.id == cleanItem.id }) else {
            throw MedicationError.saveFailed
        }

        // Ownership never changes on edit; a caregiver must be linked to the medication's owner.
        let ownerId = allMedications[index].patientId
        cleanItem.patientId = ownerId
        if let user = currentUser, user.role == .caregiver {
            if let targetPatientId, targetPatientId != ownerId {
                throw MedicationError.unauthorizedCaregiver
            }
            try validateCaregiverPermission(caregiverId: user.id, targetPatientId: ownerId)
        }

        allMedications[index] = cleanItem
        persistMedications()
        refreshDerivedState()

        // Reschedule reminder
        _ = await scheduleReminder(for: item)

        if let user = currentUser {
            if user.role == .caregiver {
                showToast("تم حفظ تعديلات دواء \"\(cleanItem.name)\" وتحديثها في جدول المستفيد.")
            } else if !RelationshipService.shared.activeRelationships.isEmpty {
                showToast("تم حفظ تعديلات دواء \"\(cleanItem.name)\" بنجاح وتحديث جدولك.")
                // Instantly notify caregiver
                RelationshipService.shared.showToast("🔔 قام \(user.displayName) بتعديل دواء \"\(cleanItem.name)\" (\(cleanItem.dosage) • \(cleanItem.timeString))")
            } else {
                showToast("تم حفظ تعديلات دواء \"\(cleanItem.name)\" بنجاح.")
            }
        } else {
            showToast("تم حفظ تعديلات دواء \"\(cleanItem.name)\" بنجاح.")
        }
    }

    // MARK: - Use-Case 11 (UC-11): Delete Medication
    /// Direct permanent deletion (when no caregiver is connected or when requested directly)
    public func deleteMedicationDirectly(id: UUID) {
        if let item = allMedications.first(where: { $0.id == id }) {
            // UC-11 S#5: Cancel future scheduled reminders
            cancelReminder(id: id)
            // UC-11 S#4: Remove medication from active medication list and update system database
            allMedications.removeAll(where: { $0.id == id })
            pendingDeletionRequests.removeAll(where: { $0.medicationId == id })
            persistMedications()
            persistDeletionRequests()
            // UC-11 S#6: Refresh medication list and Home Page to reflect deletion
            refreshDerivedState()
            showToast("تم حذف دواء \"\(item.name)\" بنجاح.")
        }
    }

    /// Legacy alias for direct deletion
    public func deleteMedication(id: UUID) {
        deleteMedicationDirectly(id: id)
    }

    /// UC-11: Caregiver deletes a medication directly
    /// Removes it permanently from the patient's schedule, cancels reminders, and updates views immediately.
    public func deleteMedicationByCaregiver(id: UUID, patientName: String? = nil) {
        guard let item = allMedications.first(where: { $0.id == id }) else { return }
        // UC-11 S#5: Cancels the medication's future scheduled reminders
        cancelReminder(id: id)
        // UC-11 S#4: Removes the medication from active medication list
        allMedications.removeAll(where: { $0.id == id })
        pendingDeletionRequests.removeAll(where: { $0.medicationId == id })
        persistMedications()
        persistDeletionRequests()
        // UC-11 S#6: Refreshes medication list and Home Page
        refreshDerivedState()

        let target = patientName != nil ? " من جدول \(patientName!)" : ""
        showToast("تم حذف دواء \"\(item.name)\"\(target) نهائياً وإلغاء جميع التذكيرات.")
    }

    /// UC-11 Collaborative Workflow: Patient requests deletion of a medication
    /// If connected to caregivers: marks medication as pending deletion and sends one request to every caregiver
    /// linked to this patient. Any one of them can approve or reject it.
    /// If not connected to any caregiver: deletes directly.
    /// - Parameter caregivers: Relationships to consider; only active links to `patient` are used.
    public func requestMedicationDeletionByPatient(
        medicationId: UUID,
        patient: UserIdentity,
        caregivers: [ActiveRelationship]
    ) {
        guard let item = allMedications.first(where: { $0.id == medicationId && $0.patientId == patient.id }) else { return }

        var caregiverIds: [String] = []
        for rel in caregivers where rel.patientId == patient.id && rel.isActive && !caregiverIds.contains(rel.caregiverId) {
            caregiverIds.append(rel.caregiverId)
        }

        // If no caregiver is connected, delete directly
        if caregiverIds.isEmpty {
            deleteMedicationDirectly(id: medicationId)
            return
        }

        // Mark medication as pending deletion
        if let index = allMedications.firstIndex(where: { $0.id == medicationId }) {
            allMedications[index].isPendingDeletion = true
            persistMedications()
            refreshDerivedState()
        }

        if let existingIndex = pendingDeletionRequests.firstIndex(where: { $0.medicationId == medicationId }) {
            // Already requested: make sure every currently linked caregiver can act on it
            pendingDeletionRequests[existingIndex].caregiverIds = caregiverIds
        } else {
            pendingDeletionRequests.append(
                MedicationDeletionRequest(
                    medicationId: medicationId,
                    medicationName: item.name,
                    dosage: item.dosage,
                    timeString: item.timeString,
                    patientId: patient.id,
                    patientDisplayName: patient.displayName,
                    caregiverIds: caregiverIds
                )
            )
        }
        persistDeletionRequests()

        if caregiverIds.count > 1 {
            showToast("تم إرسال طلب حذف دواء \"\(item.name)\" إلى مقدمي الرعاية المرتبطين بك للموافقة.")
        } else {
            showToast("تم إرسال طلب حذف دواء \"\(item.name)\" إلى مقدم الرعاية للموافقة.")
        }
    }

    /// True when `caregiverId` may approve or reject `request`: it was sent to them and they are still
    /// actively linked to the patient. Requests saved without recipients accept any linked caregiver.
    public func canRespond(to request: MedicationDeletionRequest, caregiverId: String) -> Bool {
        let isLinked = RelationshipService.shared.activeRelationships.contains {
            $0.caregiverId == caregiverId && $0.patientId == request.patientId && $0.isActive
        }
        guard isLinked else { return false }
        return request.caregiverIds.isEmpty || request.caregiverIds.contains(caregiverId)
    }

    /// Pending deletion requests that `caregiverId` can approve or reject.
    public func deletionRequests(forCaregiver caregiverId: String) -> [MedicationDeletionRequest] {
        pendingDeletionRequests.filter { canRespond(to: $0, caregiverId: caregiverId) }
    }

    /// Called after a patient–caregiver link ends. That caregiver is removed from the patient's pending
    /// deletion requests; a request left with no linked caregiver is withdrawn and its medication stays scheduled.
    public func relationshipEnded(patientId: String, caregiverId: String) {
        let stillLinked = Set(
            RelationshipService.shared.activeRelationships
                .filter { $0.patientId == patientId && $0.isActive }
                .map(\.caregiverId)
        )

        var withdrawnMedicationIds: [UUID] = []
        var changed = false
        for idx in pendingDeletionRequests.indices.reversed() where pendingDeletionRequests[idx].patientId == patientId {
            let original = pendingDeletionRequests[idx].caregiverIds
            let remaining = original.filter { $0 != caregiverId }
            // Requests saved without recipients stay open while any caregiver is still linked.
            let hasRecipient = original.isEmpty
                ? !stillLinked.isEmpty
                : remaining.contains { stillLinked.contains($0) }
            if hasRecipient {
                if remaining != pendingDeletionRequests[idx].caregiverIds {
                    pendingDeletionRequests[idx].caregiverIds = remaining
                    changed = true
                }
            } else {
                withdrawnMedicationIds.append(pendingDeletionRequests[idx].medicationId)
                pendingDeletionRequests.remove(at: idx)
                changed = true
            }
        }
        guard changed else { return }

        for idx in allMedications.indices where withdrawnMedicationIds.contains(allMedications[idx].id) {
            allMedications[idx].isPendingDeletion = false
        }
        if !withdrawnMedicationIds.isEmpty {
            persistMedications()
            refreshDerivedState()
        }
        persistDeletionRequests()
    }

    /// UC-11: Caregiver approves deletion request -> permanently deletes medication from patient's schedule
    public func approveDeletionRequest(requestId: UUID, by caregiver: UserIdentity) {
        guard let reqIndex = pendingDeletionRequests.firstIndex(where: { $0.id == requestId }) else { return }
        let request = pendingDeletionRequests[reqIndex]
        guard canRespond(to: request, caregiverId: caregiver.id) else {
            showToast("لا تملك صلاحية الرد على طلب الحذف هذا.")
            return
        }

        // 1. Cancel future reminders (UC-11 S#5)
        cancelReminder(id: request.medicationId)

        // 2. Remove medication permanently (UC-11 S#4)
        allMedications.removeAll(where: { $0.id == request.medicationId })

        // 3. Remove request
        pendingDeletionRequests.remove(at: reqIndex)

        // 4. Persist and refresh (UC-11 S#6)
        persistMedications()
        persistDeletionRequests()
        refreshDerivedState()

        showToast("تمت الموافقة على حذف دواء \"\(request.medicationName)\" وحذفه نهائياً.")
    }

    /// UC-11: Caregiver rejects deletion request -> keeps medication active in patient's schedule
    public func rejectDeletionRequest(requestId: UUID, by caregiver: UserIdentity) {
        guard let reqIndex = pendingDeletionRequests.firstIndex(where: { $0.id == requestId }) else { return }
        let request = pendingDeletionRequests[reqIndex]
        guard canRespond(to: request, caregiverId: caregiver.id) else {
            showToast("لا تملك صلاحية الرد على طلب الحذف هذا.")
            return
        }

        // 1. Restore medication (clear pending flag, keep active in schedule)
        if let medIndex = allMedications.firstIndex(where: { $0.id == request.medicationId }) {
            allMedications[medIndex].isPendingDeletion = false
            persistMedications()
            refreshDerivedState()
        }

        // 2. Remove request
        pendingDeletionRequests.remove(at: reqIndex)
        persistDeletionRequests()

        showToast("تم رفض حذف دواء \"\(request.medicationName)\" والاحتفاظ به في جدول المستفيد.")
    }

    // MARK: - UC-6 Confirm Dose Taken
    /// UC-6: Confirms dose taken, records timestamp, updates status and notifies caregivers.
    /// Single unified entry point for all dose confirmations; ignores duplicate, early, or expired confirmations.
    @discardableResult
    public func confirmDoseTaken(id: UUID, patient: UserIdentity) -> Bool {
        guard let index = allMedications.firstIndex(where: { $0.id == id && $0.patientId == patient.id }) else { return false }
        let now = AppClock.shared.now

        // Guard against double-tap / already confirmed dose or out-of-window dose
        let currentState = doseInteractionState(for: allMedications[index], at: now)
        guard !allMedications[index].isTaken, (currentState == .dueOnTime || currentState == .overdueLate) else {
            if currentState == .missed {
                AdherenceService.shared.recordDoseMissedIfNeeded(
                    medication: allMedications[index],
                    patientId: patient.id,
                    on: now
                )
                showToast("انتهى وقت تأكيد جرعة «\(allMedications[index].name)» وتم تسجيلها كجرعة فائتة.")
            }
            return false
        }

        let medName = allMedications[index].name
        let isCarryover = hasActiveCarryoverFromYesterday(allMedications[index], at: now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)

        if isCarryover, let yesterday {
            // Confirm yesterday's midnight-crossing occurrence without marking today's future dose as taken
            AdherenceService.shared.recordDoseTaken(
                medication: allMedications[index],
                patientId: patient.id,
                takenAt: now,
                scheduledDay: yesterday
            )
        } else {
            allMedications[index].isTaken = true
            allMedications[index].takenAt = now
            persistMedications()

            // UC-7: Record in dose log for weekly adherence report
            AdherenceService.shared.recordDoseTaken(
                medication: allMedications[index],
                patientId: patient.id,
                takenAt: now,
                scheduledDay: now
            )
        }

        // Refresh derived schedule and remainingDoses count
        refreshDerivedState()

        // UC-5: Dose confirmed -> cancel caregiver missed dose alert
        cancelMissedDoseAlert(id: id)
        if isCarryover, let med = allMedications.first(where: { $0.id == id }) {
            // Only yesterday's dose was confirmed; today's dose is still open and needs its alert.
            Task { await self.scheduleMissedDoseAlert(for: med) }
        }

        // UC-6 S#6: Notify connected caregivers
        RelationshipService.shared.notifyCaregiversDoseTaken(
            medicationName: medName,
            patientName: patient.displayName
        )

        if self.remainingDoses > 0 {
            showToast("تم تأكيد جرعة «\(medName)». باقي \(self.remainingDoses) جرعات اليوم")
        } else {
            showToast("أكملت جميع جرعات اليوم")
        }
        return true
    }

    // MARK: - Notification Action Handling (Quick Actions & Notification Taps)
    public func handleNotificationAction(medicationId: UUID, actionIdentifier: String, appState: AppState?) {
        refreshDerivedState()
        guard let med = allMedications.first(where: { $0.id == medicationId }) else { return }

        let now = AppClock.shared.now
        let state = doseInteractionState(for: med, at: now)

        if actionIdentifier == Self.confirmDoseActionIdentifier {
            switch state {
            case .dueOnTime, .overdueLate:
                if let patient = appState?.currentIdentity ?? KeychainService.shared.loadUserIdentity() {
                    _ = confirmDoseTaken(id: medicationId, patient: patient)
                }
            case .missed:
                reconcilePastAndMidnightDoses(at: now)
                showToast("انتهى وقت تأكيد جرعة «\(med.name)» وتم تسجيلها كجرعة فائتة.")
            case .upcomingBeforeWindow:
                showToast("لم يحن موعد جرعة «\(med.name)» بعد (الموعد الساعة \(med.timeString.westernNumerals)).")
            case .taken:
                showToast("تم تأكيد جرعة «\(med.name)» مسبقاً.")
            }
        } else {
            if state == .missed {
                reconcilePastAndMidnightDoses(at: now)
                showToast("انتهى وقت تأكيد جرعة «\(med.name)» وتم تسجيلها كجرعة فائتة.")
            }
            appState?.openDoseConfirmation(for: medicationId)
        }
    }

    // MARK: - Validation Helpers (UC-3)
    private func validateRequiredFields(name: String, dosage: String, timeString: String) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDosage = dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTime = timeString.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanName.isEmpty || cleanDosage.isEmpty || cleanTime.isEmpty {
            throw MedicationError.missingRequiredFields
        }

        if cleanDosage.count < 2 {
            throw MedicationError.invalidDosage
        }
    }

    private func validateImageData(_ data: Data) throws {
        if data.count > maxImageSizeBytes {
            throw MedicationError.imageTooLarge
        }

        // Basic image signature check (JPEG, PNG, HEIC)
        let header = [UInt8](data.prefix(4))
        let isPNG = header.starts(with: [0x89, 0x50, 0x4E, 0x47])
        let isJPEG = header.starts(with: [0xFF, 0xD8])
        let isHEIC = data.count > 12 && data.prefix(12).contains(0x66) // 'ftyp'
        
        // If UIImage can decode it, it's valid
        if !isPNG && !isJPEG && !isHEIC && UIImage(data: data) == nil {
            throw MedicationError.unsupportedImageFormat
        }
    }

    /// A caregiver may change a patient's schedule only through an active link to that exact patient.
    private func validateCaregiverPermission(caregiverId: String, targetPatientId: String?) throws {
        guard let targetPatientId else {
            throw MedicationError.unauthorizedCaregiver
        }
        let activeRels = RelationshipService.shared.activeRelationships
        let hasActiveConnection = activeRels.contains { rel in
            rel.caregiverId == caregiverId && rel.isActive && rel.patientId == targetPatientId
        }

        if !hasActiveConnection {
            throw MedicationError.unauthorizedCaregiver
        }
    }

    // MARK: - UC-3 S#6 & S#9: Notification Scheduling
    public func scheduleReminder(for item: MedicationItem) async -> Bool {
        let enabled = UserDefaults.standard.object(forKey: "dawai_notifications_enabled") as? Bool ?? true
        guard enabled else {
            return true
        }

        let center = UNUserNotificationCenter.current()

        do {
            let settings = await center.notificationSettings()
            var isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional

            if settings.authorizationStatus == .notDetermined {
                isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            }

            guard isAuthorized else {
                return false
            }

            // Create notification content (UC-4 S#3: payload with medicationId)
            let content = UNMutableNotificationContent()
            content.title = "تذكير بموعد دواء: \(item.name)"
            content.body = "حان موعد تناول الجرعة (\(item.dosage)) - \(item.timeString)"
            if let instructions = item.instructions, !instructions.isEmpty {
                content.body += "\nتعليمات: \(instructions)"
            }
            content.sound = .default
            content.categoryIdentifier = Self.doseReminderCategoryIdentifier
            content.userInfo = [
                "medicationId": item.id.uuidString,
                "type": "dose_reminder"
            ]

            // Parse time trigger
            var dateComponents = DateComponents()
            if let date = item.scheduledDate {
                dateComponents = Calendar.current.dateComponents([.hour, .minute], from: date)
            } else {
                dateComponents.hour = 12
                dateComponents.minute = 0
            }

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: "medication_reminder_\(item.id.uuidString)",
                content: content,
                trigger: trigger
            )

            try await center.add(request)

            // UC-5 S#2 & S#3: Schedule Missed-Dose Alert for Caregiver (30 minutes after scheduled time)
            await scheduleMissedDoseAlert(for: item)

            return true
        } catch {
            return false
        }
    }

    /// UC-5 S#2 & S#3: Schedules the repeating missed-dose alert 30 minutes after `item`'s scheduled time.
    /// Does nothing when reminders are switched off in Settings or notifications are not authorized.
    public func scheduleMissedDoseAlert(for item: MedicationItem) async {
        let enabled = UserDefaults.standard.object(forKey: "dawai_notifications_enabled") as? Bool ?? true
        guard enabled else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let missedContent = UNMutableNotificationContent()
        missedContent.title = "تنبيه تأخر جرعة: \(item.name)"
        missedContent.body = "لم يتم تأكيد أخذ جرعة \(item.name) (\(item.dosage)) بعد مرور 30 دقيقة من موعدها."
        missedContent.sound = .default
        missedContent.userInfo = [
            "medicationId": item.id.uuidString,
            "medicationName": item.name,
            "dosage": item.dosage,
            "patientId": item.patientId,
            "type": "missed_dose_alert"
        ]

        var missedComps = DateComponents()
        let schedMinutes = scheduledMinutes(for: item)
        let alertMinutes = (schedMinutes + DoseWindowConfig.lateThresholdMinutes) % 1440
        missedComps.hour = alertMinutes / 60
        missedComps.minute = alertMinutes % 60

        let missedTrigger = UNCalendarNotificationTrigger(dateMatching: missedComps, repeats: true)
        let missedRequest = UNNotificationRequest(
            identifier: "medication_missed_dose_\(item.id.uuidString)",
            content: missedContent,
            trigger: missedTrigger
        )
        try? await center.add(missedRequest)
    }

    public func cancelReminder(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [
                "medication_reminder_\(id.uuidString)",
                "medication_missed_dose_\(id.uuidString)"
            ]
        )
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [
                "medication_reminder_\(id.uuidString)",
                "medication_missed_dose_\(id.uuidString)"
            ]
        )
    }

    /// UC-5: Cancels pending and delivered missed dose alert when dose is confirmed
    public func cancelMissedDoseAlert(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["medication_missed_dose_\(id.uuidString)"]
        )
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: ["medication_missed_dose_\(id.uuidString)"]
        )
    }

    /// Proactively requests notification permissions if not yet determined (e.g. on first Home view appearance)
    @discardableResult
    public func requestNotificationPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                UserDefaults.standard.set(granted, forKey: "dawai_notifications_enabled")
                return granted
            } catch {
                return false
            }
        }
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Simulator testing helper: triggers an immediate reminder after `delaySeconds` with notification payload (UC-4)
    @discardableResult
    public func simulateInstantReminder(for item: MedicationItem, delaySeconds: TimeInterval = 3) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "تذكير بموعد دواء: \(item.name)"
        content.body = "حان موعد تناول الجرعة (\(item.dosage)) - \(item.timeString)"
        if let instructions = item.instructions, !instructions.isEmpty {
            content.body += "\nتعليمات: \(instructions)"
        }
        content.sound = .default
        content.categoryIdentifier = Self.doseReminderCategoryIdentifier
        content.userInfo = [
            "medicationId": item.id.uuidString,
            "type": "dose_reminder"
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delaySeconds, 1), repeats: false)
        let request = UNNotificationRequest(
            identifier: "sim_instant_\(item.id.uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            showToast("سيصلك إشعار التذكير لدواء \"\(item.name)\" بعد \(Int(delaySeconds)) ثوانٍ.")
            return true
        } catch {
            return false
        }
    }

    /// Simulator testing helper: triggers an immediate missed-dose alert for Caregiver after `delaySeconds` (UC-5)
    @discardableResult
    public func simulateInstantMissedDoseAlert(for item: MedicationItem, delaySeconds: TimeInterval = 3) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "تنبيه تأخر جرعة: \(item.name)"
        content.body = "لم يتم تأكيد أخذ جرعة \(item.name) (\(item.dosage)) بعد مرور \(DoseWindowConfig.lateThresholdMinutes) دقيقة من موعدها."
        content.sound = .default
        content.userInfo = [
            "medicationId": item.id.uuidString,
            "medicationName": item.name,
            "dosage": item.dosage,
            "patientId": item.patientId,
            "type": "missed_dose_alert"
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delaySeconds, 1), repeats: false)
        let request = UNNotificationRequest(
            identifier: "sim_instant_missed_\(item.id.uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            showToast("سيصلك تنبيه تأخر جرعة \"\(item.name)\" بعد \(Int(delaySeconds)) ثوانٍ.")
            return true
        } catch {
            return false
        }
    }

    // MARK: - Notification Management (Backend Engine)
    public enum NotificationToggleResult {
        case enabled(scheduledCount: Int)
        case disabled
        case permissionDenied
        case failed(Error)
    }

    /// Checks the real iOS system authorization status
    public func checkSystemNotificationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    /// Toggles reminders on or off based on Settings preference with full system integration
    @discardableResult
    public func setNotificationsEnabled(_ enabled: Bool) async -> NotificationToggleResult {
        let center = UNUserNotificationCenter.current()

        if !enabled {
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
            UserDefaults.standard.set(false, forKey: "dawai_notifications_enabled")
            showToast("تم إيقاف تنبيهات مواعيد الأدوية")
            return .disabled
        } else {
            let settings = await center.notificationSettings()
            var isAuthorized = false

            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                isAuthorized = true
            } else if settings.authorizationStatus == .notDetermined {
                do {
                    isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                } catch {
                    return .failed(error)
                }
            } else if settings.authorizationStatus == .denied {
                UserDefaults.standard.set(false, forKey: "dawai_notifications_enabled")
                return .permissionDenied
            }

            guard isAuthorized else {
                UserDefaults.standard.set(false, forKey: "dawai_notifications_enabled")
                return .permissionDenied
            }

            UserDefaults.standard.set(true, forKey: "dawai_notifications_enabled")

            // Reschedule reminders for all upcoming medications
            var scheduledCount = 0
            for med in allMedications where !med.isTaken {
                let success = await scheduleReminder(for: med)
                if success { scheduledCount += 1 }
            }

            if scheduledCount > 0 {
                showToast("تم تفعيل تنبيهات مواعيد الأدوية (\(scheduledCount) مواعيد)")
            } else {
                showToast("تم تفعيل تنبيهات مواعيد الأدوية بنجاح")
            }
            return .enabled(scheduledCount: scheduledCount)
        }
    }

    /// Toggles reminders on or off based on Settings preference
    public func updateNotificationPreference(enabled: Bool) async {
        _ = await setNotificationsEnabled(enabled)
    }

    // MARK: - Toast helper
    public func showToast(_ message: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            self.toastMessage = message
        }
    }

    public func dismissToast() {
        withAnimation(.easeInOut(duration: 0.25)) {
            self.toastMessage = nil
        }
    }
}

// MARK: - UC-4 S#4: Notification Center Delegate
public final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = NotificationDelegate()

    public weak var appState: AppState?

    private override init() {
        super.init()
    }

    public func configure(with appState: AppState) {
        self.appState = appState
        UNUserNotificationCenter.current().delegate = self
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let notifType = userInfo["type"] as? String ?? "dose_reminder"

        if notifType == "missed_dose_alert" {
            // UC-5 S#5: Caregiver opens missed-dose notification -> system routes directly to patient detail
            let medName = userInfo["medicationName"] as? String ?? "الدواء"
            let dosage = userInfo["dosage"] as? String ?? ""
            let payloadPatientId = userInfo["patientId"] as? String
            let medicationId = (userInfo["medicationId"] as? String).flatMap(UUID.init(uuidString:))
            Task { @MainActor in
                // Resolve the real patient: from the payload, or (for alerts scheduled before the
                // payload carried it) from the medication's owner.
                let patientId = payloadPatientId
                    ?? medicationId.flatMap { id in MedicationService.shared.allMedications.first(where: { $0.id == id })?.patientId }
                let relationship = RelationshipService.shared.activeRelationships.first { $0.patientId == patientId && $0.isActive }
                let beneficiary = BeneficiarySummary(
                    id: relationship?.id ?? UUID(),
                    patientId: patientId,
                    name: relationship?.patientDisplayName ?? "المستفيد",
                    hasDelayAlert: true,
                    delayNotice: "30 د تأخير، \(medName)",
                    scheduledTime: nil,
                    isInvitation: false,
                    delayedMedicationName: medName,
                    delayedDosage: dosage,
                    phoneNumber: "0501234567"
                )
                self.appState?.openCaregiverPatientDetail(for: beneficiary)
            }
        } else if let medIdString = userInfo["medicationId"] as? String,
                  let medId = UUID(uuidString: medIdString) {
            let actionId = response.actionIdentifier
            Task { @MainActor in
                MedicationService.shared.handleNotificationAction(
                    medicationId: medId,
                    actionIdentifier: actionId,
                    appState: self.appState
                )
                completionHandler()
            }
            return
        }
        completionHandler()
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }
}
