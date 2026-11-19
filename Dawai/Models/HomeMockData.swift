//
//  HomeMockData.swift
//  Dawai
//
//  Lightweight dummy models and preview data for Patient & Caregiver home views.
//  Designed for easy deletion/replacement once real persistence and backend are wired up.
//

import Foundation

// MARK: - Medication Schedule Type & Waking Hours Defaults
public enum MedicationScheduleType: String, Codable, Equatable, Sendable {
    case daily = "daily"
    case specificWeekdays = "specific_weekdays"
    case everyOtherDay = "every_other_day"
    case asNeeded = "as_needed"
}

public enum MedicationWakingHoursDefaults {
    /// Returns default dose times (minutes after midnight) spread over waking hours:
    /// 1 dose -> [8:00 ص] (480)
    /// 2 doses -> [8:00 ص (480), 8:00 م (1200)]
    /// 3 doses -> [8:00 ص (480), 2:00 م (840), 8:00 م (1200)]
    /// 4 doses -> [8:00 ص (480), 12:00 م (720), 4:00 م (960), 8:00 م (1200)]
    public static func defaultMinutes(forCount count: Int) -> [Int] {
        switch count {
        case 1:
            return [8 * 60] // 08:00 AM
        case 2:
            return [8 * 60, 20 * 60] // 08:00 AM, 08:00 PM
        case 3:
            return [8 * 60, 14 * 60, 20 * 60] // 08:00 AM, 02:00 PM, 08:00 PM
        case 4:
            return [8 * 60, 12 * 60, 16 * 60, 20 * 60] // 08:00 AM, 12:00 PM, 04:00 PM, 08:00 PM
        default:
            return [8 * 60]
        }
    }
}

// MARK: - Medication Weekday Model
/// Gregorian weekday values matching `Calendar.current.component(.weekday, from:)` (1 = Sunday ... 7 = Saturday).
public enum MedicationWeekday: Int, CaseIterable, Codable, Hashable, Comparable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    public var id: Int { rawValue }

    public static func < (lhs: MedicationWeekday, rhs: MedicationWeekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var optionTitle: String {
        switch self {
        case .sunday: return "الأحد"
        case .monday: return "الاثنين"
        case .tuesday: return "الثلاثاء"
        case .wednesday: return "الأربعاء"
        case .thursday: return "الخميس"
        case .friday: return "الجمعة"
        case .saturday: return "السبت"
        }
    }

    private var keywords: [String] {
        switch self {
        case .sunday: return ["الاحد", "الأحد"]
        case .monday: return ["الاثنين", "الإثنين"]
        case .tuesday: return ["الثلاثاء"]
        case .wednesday: return ["الاربعاء", "الأربعاء"]
        case .thursday: return ["الخميس"]
        case .friday: return ["الجمعه", "الجمعة"]
        case .saturday: return ["السبت"]
        }
    }

    /// Parses legacy Arabic day labels into Gregorian weekday numbers (`1...7`).
    /// Returns an empty set when the schedule repeats every day (all 7 days or `"كل يوم"`).
    public static func parseWeekdayNumbers(from days: [String]) -> Set<Int> {
        if days.isEmpty || days.contains("كل يوم") || days.contains("يومياً") || days.contains("دائم") {
            return []
        }
        var result = Set<Int>()
        for weekday in MedicationWeekday.allCases {
            let isSelected = days.contains { day in
                weekday.keywords.contains { keyword in day.contains(keyword) }
            }
            if isSelected {
                result.insert(weekday.rawValue)
            }
        }
        return result.count == 7 ? [] : result
    }

    /// Converts structured weekday numbers (`1...7`) into display labels for the UI.
    public static func displayDays(from weekdays: Set<Int>) -> [String] {
        let valid = weekdays.filter { (1...7).contains($0) }
        if valid.isEmpty || valid.count == 7 {
            return ["كل يوم"]
        }
        return valid.sorted().compactMap { MedicationWeekday(rawValue: $0)?.optionTitle }
    }
}

// MARK: - Medication Item Model
public struct MedicationItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    /// Identity id of the patient who owns this medication. Medication lists, missed-dose checks
    /// and caregiver screens all filter by this value. It is also the ownership key for future sync.
    public var patientId: String
    public var name: String
    public var dosage: String
    public var timeString: String
    public var scheduledDate: Date?
    public var days: [String]
    /// Structured Gregorian weekday numbers (`1 = Sunday ... 7 = Saturday`). Empty means every day.
    public var selectedWeekdays: Set<Int>
    public var frequency: String
    public var duration: String
    public var instructions: String?
    public var imageData: Data?
    public var isTaken: Bool
    public var takenAt: Date?
    /// Maps slot time in minutes from midnight (0..<1440) to the confirmation timestamp on the current day.
    public var takenSlotsToday: [Int: Date]
    public var createdAt: Date
    public var scheduleUpdatedAt: Date
    public var isPendingDeletion: Bool

    // Structured Schedule Fields
    public var scheduleType: MedicationScheduleType
    public var customDoseTimesMinutes: [Int]
    public var startDate: Date
    public var endDate: Date?

    enum CodingKeys: String, CodingKey {
        case id, patientId, name, dosage, timeString, scheduledDate, days, selectedWeekdays, frequency, duration, instructions, imageData, isTaken, takenAt, takenSlotsToday, createdAt, scheduleUpdatedAt, isPendingDeletion
        case scheduleType, customDoseTimesMinutes, startDate, endDate
    }

    public init(
        id: UUID = UUID(),
        patientId: String = MedicationItem.currentIdentityPatientId,
        name: String,
        dosage: String,
        timeString: String,
        scheduledDate: Date? = nil,
        days: [String] = ["كل يوم"],
        selectedWeekdays: Set<Int>? = nil,
        frequency: String = "مرة يومياً",
        duration: String = "مستمر",
        instructions: String? = nil,
        imageData: Data? = nil,
        isTaken: Bool = false,
        takenAt: Date? = nil,
        takenSlotsToday: [Int: Date] = [:],
        createdAt: Date = AppClock.shared.now,
        scheduleUpdatedAt: Date? = nil,
        isPendingDeletion: Bool = false,
        scheduleType: MedicationScheduleType? = nil,
        customDoseTimesMinutes: [Int]? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.id = id
        self.patientId = patientId
        self.name = name
        self.dosage = dosage
        self.timeString = timeString
        self.scheduledDate = scheduledDate

        let resolvedWeekdays: Set<Int>
        let resolvedDays: [String]
        if let selectedWeekdays {
            let normalized = Set(selectedWeekdays.filter { (1...7).contains($0) })
            resolvedWeekdays = normalized.count == 7 ? [] : normalized
            resolvedDays = (days == ["كل يوم"] && !resolvedWeekdays.isEmpty)
                ? MedicationWeekday.displayDays(from: resolvedWeekdays)
                : days
        } else {
            resolvedDays = days
            resolvedWeekdays = MedicationWeekday.parseWeekdayNumbers(from: days)
        }
        self.days = resolvedDays
        self.selectedWeekdays = resolvedWeekdays

        self.frequency = frequency
        self.duration = duration
        self.instructions = instructions
        self.imageData = imageData
        self.isTaken = isTaken
        self.takenAt = takenAt
        self.takenSlotsToday = takenSlotsToday
        self.createdAt = createdAt
        self.scheduleUpdatedAt = scheduleUpdatedAt ?? createdAt
        self.isPendingDeletion = isPendingDeletion

        let effectiveStart = startDate ?? createdAt
        self.startDate = effectiveStart
        self.endDate = endDate

        // Derive or set scheduleType
        let resolvedScheduleType: MedicationScheduleType
        if let scheduleType {
            resolvedScheduleType = scheduleType
        } else {
            if resolvedDays.contains("عند الحاجة") || resolvedDays.contains("عند اللزوم") || frequency.contains("عند الحاجة") || frequency.contains("عند اللزوم") {
                resolvedScheduleType = .asNeeded
            } else if resolvedDays.contains("يوم بعد يوم") || frequency.contains("يوم بعد يوم") || frequency.contains("كل يومين") || frequency.contains("كل 3 أيام") {
                resolvedScheduleType = .everyOtherDay
            } else if !resolvedWeekdays.isEmpty {
                resolvedScheduleType = .specificWeekdays
            } else {
                resolvedScheduleType = .daily
            }
        }
        self.scheduleType = resolvedScheduleType

        // Derive or set customDoseTimesMinutes
        let resolvedDoseTimes: [Int]
        if let customDoseTimesMinutes, !customDoseTimesMinutes.isEmpty {
            resolvedDoseTimes = customDoseTimesMinutes.sorted()
        } else {
            let primaryMinute: Int = {
                if let d = scheduledDate {
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: d)
                    return (comps.hour ?? 8) * 60 + (comps.minute ?? 0)
                }
                return MedicationItem.parseMinutes(from: timeString)
            }()
            let count = MedicationItem.parseDoseCount(from: frequency)
            if count <= 1 {
                resolvedDoseTimes = [primaryMinute]
            } else {
                let defaults = MedicationWakingHoursDefaults.defaultMinutes(forCount: count)
                var times = [primaryMinute]
                for def in defaults.dropFirst() {
                    times.append(def)
                }
                resolvedDoseTimes = times.sorted()
            }
        }
        self.customDoseTimesMinutes = resolvedDoseTimes
    }

    /// Convenience initializer accepting `selectedWeekdays` as `[Int]?`
    public init(
        id: UUID = UUID(),
        patientId: String = MedicationItem.currentIdentityPatientId,
        name: String,
        dosage: String,
        timeString: String,
        scheduledDate: Date? = nil,
        days: [String] = ["كل يوم"],
        selectedWeekdays: [Int]?,
        frequency: String = "مرة يومياً",
        duration: String = "مستمر",
        instructions: String? = nil,
        imageData: Data? = nil,
        isTaken: Bool = false,
        takenAt: Date? = nil,
        takenSlotsToday: [Int: Date] = [:],
        createdAt: Date = AppClock.shared.now,
        scheduleUpdatedAt: Date? = nil,
        isPendingDeletion: Bool = false,
        scheduleType: MedicationScheduleType? = nil,
        customDoseTimesMinutes: [Int]? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.init(
            id: id,
            patientId: patientId,
            name: name,
            dosage: dosage,
            timeString: timeString,
            scheduledDate: scheduledDate,
            days: days,
            selectedWeekdays: selectedWeekdays.map { Set($0) },
            frequency: frequency,
            duration: duration,
            instructions: instructions,
            imageData: imageData,
            isTaken: isTaken,
            takenAt: takenAt,
            takenSlotsToday: takenSlotsToday,
            createdAt: createdAt,
            scheduleUpdatedAt: scheduleUpdatedAt,
            isPendingDeletion: isPendingDeletion,
            scheduleType: scheduleType,
            customDoseTimesMinutes: customDoseTimesMinutes,
            startDate: startDate,
            endDate: endDate
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decId = try container.decode(UUID.self, forKey: .id)
        let decPatientId = try container.decodeIfPresent(String.self, forKey: .patientId)
            ?? (decoder.userInfo[MedicationItem.legacyPatientIdUserInfoKey] as? String)
            ?? MedicationItem.currentIdentityPatientId
        let decName = try container.decode(String.self, forKey: .name)
        let decDosage = try container.decode(String.self, forKey: .dosage)
        let decTimeString = try container.decode(String.self, forKey: .timeString)
        let decScheduledDate = try container.decodeIfPresent(Date.self, forKey: .scheduledDate)

        let decodedDays = try container.decodeIfPresent([String].self, forKey: .days) ?? ["كل يوم"]
        let resolvedWeekdays: Set<Int>
        let resolvedDays: [String]
        if let decodedWeekdays = try container.decodeIfPresent(Set<Int>.self, forKey: .selectedWeekdays) {
            let normalized = Set(decodedWeekdays.filter { (1...7).contains($0) })
            resolvedWeekdays = normalized.count == 7 ? [] : normalized
            resolvedDays = (decodedDays == ["كل يوم"] && !resolvedWeekdays.isEmpty)
                ? MedicationWeekday.displayDays(from: resolvedWeekdays)
                : decodedDays
        } else {
            resolvedDays = decodedDays
            resolvedWeekdays = MedicationWeekday.parseWeekdayNumbers(from: decodedDays)
        }

        let decFrequency = try container.decodeIfPresent(String.self, forKey: .frequency) ?? "مرة يومياً"
        let decDuration = try container.decodeIfPresent(String.self, forKey: .duration) ?? "دائم"
        let decInstructions = try container.decodeIfPresent(String.self, forKey: .instructions)
        let decImageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        let decIsTaken = try container.decodeIfPresent(Bool.self, forKey: .isTaken) ?? false
        let decTakenAt = try container.decodeIfPresent(Date.self, forKey: .takenAt)
        let decTakenSlotsToday = try container.decodeIfPresent([Int: Date].self, forKey: .takenSlotsToday) ?? [:]
        let decodedCreatedAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        let decScheduleUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .scheduleUpdatedAt) ?? decodedCreatedAt
        let decIsPendingDeletion = try container.decodeIfPresent(Bool.self, forKey: .isPendingDeletion) ?? false

        let decodedStartDate = try container.decodeIfPresent(Date.self, forKey: .startDate) ?? decodedCreatedAt
        var decodedEndDate = try container.decodeIfPresent(Date.self, forKey: .endDate)

        // Decode scheduleType or migrate from legacy days & frequency
        let resolvedScheduleType: MedicationScheduleType
        if let explicitType = try container.decodeIfPresent(MedicationScheduleType.self, forKey: .scheduleType) {
            resolvedScheduleType = explicitType
        } else {
            if resolvedDays.contains("عند الحاجة") || resolvedDays.contains("عند اللزوم") || decFrequency.contains("عند الحاجة") || decFrequency.contains("عند اللزوم") {
                resolvedScheduleType = .asNeeded
            } else if resolvedDays.contains("يوم بعد يوم") || decFrequency.contains("يوم بعد يوم") || decFrequency.contains("كل يومين") || decFrequency.contains("كل 3 أيام") {
                resolvedScheduleType = .everyOtherDay
            } else if !resolvedWeekdays.isEmpty {
                resolvedScheduleType = .specificWeekdays
            } else {
                resolvedScheduleType = .daily
            }
        }

        // Migrate instructions with legacy dropdown tags if found
        var migratedInstructions = decInstructions
        let specialNotes = ["على الريق", "مع الوجبات", "قبل النوم"]
        for note in specialNotes where decFrequency.contains(note) {
            if let existing = migratedInstructions, !existing.contains(note) {
                migratedInstructions = "\(existing) • \(note)"
            } else if migratedInstructions == nil {
                migratedInstructions = note
            }
        }
        if decFrequency.contains("كل 4 ساعات") {
            let note = "تؤخذ كل 4 ساعات"
            if let existing = migratedInstructions, !existing.contains(note) {
                migratedInstructions = "\(existing) • \(note)"
            } else if migratedInstructions == nil {
                migratedInstructions = note
            }
        }
        if decFrequency.contains("شهرياً") || decFrequency.contains("شهريا") {
            let note = "جرعة شهرية"
            if let existing = migratedInstructions, !existing.contains(note) {
                migratedInstructions = "\(existing) • \(note)"
            } else if migratedInstructions == nil {
                migratedInstructions = note
            }
        }

        // Migrate duration to endDate if needed
        if decodedEndDate == nil && decDuration != "دائم" && decDuration != "مستمر" {
            let calendar = Calendar.current
            if decDuration.contains("3 ايام") || decDuration.contains("3 أيام") {
                decodedEndDate = calendar.date(byAdding: .day, value: 3, to: decodedStartDate)
            } else if decDuration.contains("5 ايام") || decDuration.contains("5 أيام") {
                decodedEndDate = calendar.date(byAdding: .day, value: 5, to: decodedStartDate)
            } else if decDuration.contains("اسبوعين") || decDuration.contains("أسبوعين") {
                decodedEndDate = calendar.date(byAdding: .day, value: 14, to: decodedStartDate)
            } else if decDuration.contains("اسبوع") || decDuration.contains("أسبوع") {
                decodedEndDate = calendar.date(byAdding: .day, value: 7, to: decodedStartDate)
            } else if decDuration.contains("10") {
                decodedEndDate = calendar.date(byAdding: .day, value: 10, to: decodedStartDate)
            } else if decDuration.contains("3 اسابيع") || decDuration.contains("3 أسابيع") {
                decodedEndDate = calendar.date(byAdding: .day, value: 21, to: decodedStartDate)
            } else if decDuration.contains("4 اسابيع") || decDuration.contains("4 أسابيع") {
                decodedEndDate = calendar.date(byAdding: .day, value: 28, to: decodedStartDate)
            } else if decDuration.contains("شهر") {
                decodedEndDate = calendar.date(byAdding: .month, value: 1, to: decodedStartDate)
            }
        }

        // Decode customDoseTimesMinutes or calculate waking-hours defaults
        let resolvedDoseTimes: [Int]
        if let explicitTimes = try container.decodeIfPresent([Int].self, forKey: .customDoseTimesMinutes), !explicitTimes.isEmpty {
            resolvedDoseTimes = explicitTimes.sorted()
        } else {
            let primaryMinute: Int = {
                if let d = decScheduledDate {
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: d)
                    return (comps.hour ?? 8) * 60 + (comps.minute ?? 0)
                }
                return MedicationItem.parseMinutes(from: decTimeString)
            }()
            let count = MedicationItem.parseDoseCount(from: decFrequency)
            if count <= 1 {
                resolvedDoseTimes = [primaryMinute]
            } else {
                let defaults = MedicationWakingHoursDefaults.defaultMinutes(forCount: count)
                var times = [primaryMinute]
                for def in defaults.dropFirst() {
                    times.append(def)
                }
                resolvedDoseTimes = times.sorted()
            }
        }

        self.id = decId
        self.patientId = decPatientId
        self.name = decName
        self.dosage = decDosage
        self.timeString = decTimeString
        self.scheduledDate = decScheduledDate
        self.days = resolvedDays
        self.selectedWeekdays = resolvedWeekdays
        self.frequency = decFrequency
        self.duration = decDuration
        self.instructions = migratedInstructions
        self.imageData = decImageData
        self.isTaken = decIsTaken
        self.takenAt = decTakenAt
        self.takenSlotsToday = decTakenSlotsToday
        self.createdAt = decodedCreatedAt
        self.scheduleUpdatedAt = decScheduleUpdatedAt
        self.isPendingDeletion = decIsPendingDeletion
        self.scheduleType = resolvedScheduleType
        self.customDoseTimesMinutes = resolvedDoseTimes
        self.startDate = decodedStartDate
        self.endDate = decodedEndDate
    }

    // MARK: - Helpers for Parsing Time & Frequency
    public static func parseMinutes(from timeStr: String) -> Int {
        let clean = timeStr.westernNumerals.trimmingCharacters(in: .whitespaces)
        let isPM = clean.contains("م") || clean.lowercased().contains("pm")
        let isAM = clean.contains("ص") || clean.lowercased().contains("am")

        let digits = clean.replacingOccurrences(of: "[^0-9:]", with: "", options: .regularExpression)
        let parts = digits.split(separator: ":")
        guard let hStr = parts.first, let h = Int(hStr) else { return 8 * 60 }
        let m = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0

        var hour = h
        if isPM && hour < 12 {
            hour += 12
        } else if isAM && hour == 12 {
            hour = 0
        }
        return hour * 60 + m
    }

    public static func parseDoseCount(from freq: String) -> Int {
        let clean = freq.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains("4 مرات") || clean.contains("أربع مرات") || clean.contains("كل 4 ساعات") || clean.contains("كل 6 ساعات") {
            return 4
        }
        if clean.contains("3 مرات") || clean.contains("ثلاث مرات") || clean.contains("كل 8 ساعات") {
            return 3
        }
        if clean.contains("مرتان") || clean.contains("مرتين") || clean.contains("كل 12 ساعة") {
            return 2
        }
        return 1
    }

    /// Owner used before any identity exists, and for Debug demo data shown to caregivers.
    public static let fallbackPatientId = "default_patient"

    /// Decoder `userInfo` key that supplies the owner of legacy items saved without `patientId`.
    /// Set it once per decode so the Keychain is not read for every item.
    public static let legacyPatientIdUserInfoKey = CodingUserInfoKey(rawValue: "dawai.legacyPatientId")!

    /// Identity id of the user on this device, or `fallbackPatientId` before onboarding.
    public static var currentIdentityPatientId: String {
        KeychainService.shared.loadUserIdentity()?.id ?? fallbackPatientId
    }
}

// MARK: - Use-Case 11 (UC-11): Medication Deletion Request Model
public struct MedicationDeletionRequest: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let medicationId: UUID
    public let medicationName: String
    public let dosage: String
    public let timeString: String
    public let patientId: String
    public let patientDisplayName: String
    /// Every caregiver linked to the patient when the request was made. Any one of them may approve or reject it.
    public var caregiverIds: [String]
    public let requestedAt: Date
    public var status: RequestStatus

    public enum RequestStatus: String, Codable, Sendable {
        case pending
        case approved
        case rejected
    }

    enum CodingKeys: String, CodingKey {
        case id, medicationId, medicationName, dosage, timeString, patientId, patientDisplayName, caregiverIds, requestedAt, status
        /// Single-caregiver field written by earlier versions; read only.
        case legacyCaregiverId = "caregiverId"
    }

    public init(
        id: UUID = UUID(),
        medicationId: UUID,
        medicationName: String,
        dosage: String,
        timeString: String,
        patientId: String,
        patientDisplayName: String,
        caregiverIds: [String] = [],
        requestedAt: Date = Date(),
        status: RequestStatus = .pending
    ) {
        self.id = id
        self.medicationId = medicationId
        self.medicationName = medicationName
        self.dosage = dosage
        self.timeString = timeString
        self.patientId = patientId
        self.patientDisplayName = patientDisplayName
        self.caregiverIds = caregiverIds
        self.requestedAt = requestedAt
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        medicationId = try container.decode(UUID.self, forKey: .medicationId)
        medicationName = try container.decode(String.self, forKey: .medicationName)
        dosage = try container.decode(String.self, forKey: .dosage)
        timeString = try container.decode(String.self, forKey: .timeString)
        patientId = try container.decode(String.self, forKey: .patientId)
        patientDisplayName = try container.decode(String.self, forKey: .patientDisplayName)
        if let ids = try container.decodeIfPresent([String].self, forKey: .caregiverIds) {
            caregiverIds = ids
        } else if let legacyId = try container.decodeIfPresent(String.self, forKey: .legacyCaregiverId) {
            caregiverIds = [legacyId]
        } else {
            caregiverIds = []
        }
        requestedAt = try container.decode(Date.self, forKey: .requestedAt)
        status = try container.decode(RequestStatus.self, forKey: .status)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(medicationId, forKey: .medicationId)
        try container.encode(medicationName, forKey: .medicationName)
        try container.encode(dosage, forKey: .dosage)
        try container.encode(timeString, forKey: .timeString)
        try container.encode(patientId, forKey: .patientId)
        try container.encode(patientDisplayName, forKey: .patientDisplayName)
        try container.encode(caregiverIds, forKey: .caregiverIds)
        try container.encode(requestedAt, forKey: .requestedAt)
        try container.encode(status, forKey: .status)
    }
}

// MARK: - Upcoming Dose Model
public struct UpcomingDose: Identifiable, Codable, Equatable {
    public let id: UUID
    public var medicationId: UUID
    public var slotMinutes: Int?
    public var name: String
    public var timeString: String
    public var dosage: String
    public var isTaken: Bool
    public var imageData: Data?

    enum CodingKeys: String, CodingKey {
        case id, medicationId, slotMinutes, name, timeString, dosage, isTaken, imageData
    }

    public init(
        id: UUID = UUID(),
        medicationId: UUID? = nil,
        slotMinutes: Int? = nil,
        name: String,
        timeString: String,
        dosage: String = "جرعة مجدولة",
        isTaken: Bool = false,
        imageData: Data? = nil
    ) {
        self.id = id
        self.medicationId = medicationId ?? id
        self.slotMinutes = slotMinutes
        self.name = name
        self.timeString = timeString
        self.dosage = dosage
        self.isTaken = isTaken
        self.imageData = imageData
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId = try container.decode(UUID.self, forKey: .id)
        id = decodedId
        medicationId = try container.decodeIfPresent(UUID.self, forKey: .medicationId) ?? decodedId
        slotMinutes = try container.decodeIfPresent(Int.self, forKey: .slotMinutes)
        name = try container.decode(String.self, forKey: .name)
        timeString = try container.decode(String.self, forKey: .timeString)
        dosage = try container.decode(String.self, forKey: .dosage)
        isTaken = try container.decodeIfPresent(Bool.self, forKey: .isTaken) ?? false
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
    }
}

// MARK: - Scheduled Dose Occurrence Model (Multi-Dose Per Day Support)
public struct ScheduledDose: Identifiable, Equatable {
    public let medication: MedicationItem
    public let slotMinutes: Int
    public let occurrenceDate: Date
    public let timeString: String
    public let isCarryoverFromYesterday: Bool

    public var id: String {
        "\(medication.id.uuidString)_\(slotMinutes)_\(isCarryoverFromYesterday ? "y" : "t")"
    }

    public init(
        medication: MedicationItem,
        slotMinutes: Int,
        occurrenceDate: Date,
        timeString: String,
        isCarryoverFromYesterday: Bool = false
    ) {
        self.medication = medication
        self.slotMinutes = slotMinutes
        self.occurrenceDate = occurrenceDate
        self.timeString = timeString
        self.isCarryoverFromYesterday = isCarryoverFromYesterday
    }
}

// MARK: - Caregiver Link Model
public struct CaregiverLink: Identifiable {
    public let id: UUID
    public var name: String
    public var statusText: String
    public var isPending: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        statusText: String,
        isPending: Bool = false
    ) {
        self.id = id
        self.name = name
        self.statusText = statusText
        self.isPending = isPending
    }
}

// MARK: - Beneficiary Summary Model (For Caregiver View)
public struct BeneficiarySummary: Identifiable, Equatable, Hashable {
    /// Identity of this list row only (for a linked patient, the relationship id). Never use it as a patient id.
    public let id: UUID
    /// The patient's identity id (`ActiveRelationship.patientId`). Use this for permission checks,
    /// medication filtering, reports and deletion requests. `nil` when there is no real patient behind the row.
    public var patientId: String?
    public var name: String
    public var hasDelayAlert: Bool
    public var delayNotice: String?
    public var scheduledTime: String?
    public var isInvitation: Bool
    public var delayedMedicationName: String?
    public var delayedDosage: String?
    public var phoneNumber: String?

    public init(
        id: UUID = UUID(),
        patientId: String? = nil,
        name: String,
        hasDelayAlert: Bool = false,
        delayNotice: String? = nil,
        scheduledTime: String? = nil,
        isInvitation: Bool = false,
        delayedMedicationName: String? = nil,
        delayedDosage: String? = nil,
        phoneNumber: String? = "0501234567"
    ) {
        self.id = id
        self.patientId = patientId
        self.name = name
        self.hasDelayAlert = hasDelayAlert
        self.delayNotice = delayNotice
        self.scheduledTime = scheduledTime
        self.isInvitation = isInvitation
        self.delayedMedicationName = delayedMedicationName
        self.delayedDosage = delayedDosage
        self.phoneNumber = phoneNumber
    }
}

// MARK: - Centralized Dummy Data Store (Debug builds only)
// This data is compiled out of TestFlight and App Store builds. In Debug it is loaded
// only when demo mode is switched on from Settings (see DemoModeService).
public enum HomeMockData {
    public static let activeMedication = MedicationItem(
        patientId: MedicationItem.fallbackPatientId,
        name: "اسبرين",
        dosage: "حبتان قبل الاكل",
        timeString: "الساعة 12:00 ص",
        isTaken: false
    )

    public static let upcomingDoses: [UpcomingDose] = [
        UpcomingDose(name: "ميترفين", timeString: "12:00 ص", dosage: "حبة واحدة بعد الأكل", isTaken: false),
        UpcomingDose(name: "فيتامين د", timeString: "10:00 ص", dosage: "قطرة واحدة يوميًا", isTaken: false)
    ]

    public static let patientCaregivers: [CaregiverLink] = [
        CaregiverLink(name: "سارة", statusText: "تم ارسال الدعوة في انتظار القبول", isPending: true)
    ]

    // Caregiver Data
    public static let beneficiaries: [BeneficiarySummary] = [
        BeneficiarySummary(
            patientId: MedicationItem.fallbackPatientId,
            name: "عمر",
            hasDelayAlert: true,
            delayNotice: "30 د تأخير، اسبرين (500 ملغ)",
            scheduledTime: "11:30 م",
            isInvitation: false,
            delayedMedicationName: "اسبرين",
            delayedDosage: "500 ملغ",
            phoneNumber: "0501234567"
        ),
        BeneficiarySummary(
            patientId: MedicationItem.fallbackPatientId,
            name: "خلود",
            hasDelayAlert: false,
            delayNotice: nil,
            scheduledTime: nil,
            isInvitation: false
        ),
        BeneficiarySummary(
            patientId: MedicationItem.fallbackPatientId,
            name: "احمد",
            hasDelayAlert: false,
            delayNotice: nil,
            scheduledTime: nil,
            isInvitation: false
        ),
        BeneficiarySummary(
            name: "عمر",
            hasDelayAlert: false,
            delayNotice: "ارسل لك عمر دعوة",
            scheduledTime: nil,
            isInvitation: true
        )
    ]
}
