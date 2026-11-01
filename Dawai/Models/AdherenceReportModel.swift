//
//  AdherenceReportModel.swift
//  Dawai
//
//  Use-Case 7 (UC-7): View Adherence Report
//  Data models representing dose records, weekly adherence metrics,
//  daily adherence breakdowns, and visual trend representations.
//

import Foundation
import SwiftUI

// MARK: - Dose Status Lifecycle
public enum DoseStatus: String, Codable, CaseIterable {
    case takenOnTime = "taken_on_time"
    case takenLate = "taken_late"
    case missed = "missed"
    case upcoming = "upcoming"

    public var titleArabic: String {
        switch self {
        case .takenOnTime:
            return "في الموعد"
        case .takenLate:
            return "متأخرة"
        case .missed:
            return "فائتة"
        case .upcoming:
            return "قادمة"
        }
    }

    public var systemIcon: String {
        switch self {
        case .takenOnTime:
            return "checkmark.circle.fill"
        case .takenLate:
            return "clock.badge.exclamationmark.fill"
        case .missed:
            return "xmark.circle.fill"
        case .upcoming:
            return "calendar.badge.clock"
        }
    }

    public var color: Color {
        switch self {
        case .takenOnTime:
            return Color.dawaiTaken
        case .takenLate:
            return Color.dawaiWarning
        case .missed:
            return Color(red: 220.0 / 255.0, green: 53.0 / 255.0, blue: 69.0 / 255.0)
        case .upcoming:
            return Color.secondary
        }
    }

    public var backgroundColor: Color {
        switch self {
        case .takenOnTime:
            return Color.dawaiTakenBackground
        case .takenLate:
            return Color.dawaiWarningBackground
        case .missed:
            return Color(red: 220.0 / 255.0, green: 53.0 / 255.0, blue: 69.0 / 255.0).opacity(0.12)
        case .upcoming:
            return Color.secondary.opacity(0.1)
        }
    }
}

// MARK: - Single Dose Record (Historical Dose Log)
public struct DoseRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public let patientId: String
    public let medicationId: UUID
    public var medicationName: String
    public var dosage: String
    public var scheduledDate: Date
    public var takenDate: Date?
    public var status: DoseStatus
    public var delayMinutes: Int

    public init(
        id: UUID = UUID(),
        patientId: String,
        medicationId: UUID,
        medicationName: String,
        dosage: String,
        scheduledDate: Date,
        takenDate: Date? = nil,
        status: DoseStatus = .takenOnTime,
        delayMinutes: Int = 0
    ) {
        self.id = id
        self.patientId = patientId
        self.medicationId = medicationId
        self.medicationName = medicationName
        self.dosage = dosage
        self.scheduledDate = scheduledDate
        self.takenDate = takenDate
        self.status = status
        self.delayMinutes = delayMinutes
    }
}

// MARK: - Week Period Specification (UC-7 S#3)
public struct WeekPeriod: Identifiable, Equatable, Hashable {
    public let id: Int // 0 for current week, -1 for last week, -2 for 2 weeks ago, etc.
    public let startDate: Date
    public let endDate: Date
    public let titleArabic: String
    public let dateRangeString: String

    public init(
        id: Int,
        startDate: Date,
        endDate: Date,
        titleArabic: String,
        dateRangeString: String
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.titleArabic = titleArabic
        self.dateRangeString = dateRangeString
    }
}

// MARK: - Daily Adherence Metric (UC-7 S#4, S#5)
public struct DailyAdherenceSummary: Identifiable, Equatable {
    public var id: Date { date }
    public let date: Date
    public let dayNameArabic: String
    public let dayShortArabic: String
    public let isToday: Bool
    public let isFuture: Bool
    public let scheduledCount: Int
    public let takenCount: Int
    public let takenOnTimeCount: Int
    public let takenLateCount: Int
    public let missedCount: Int
    public let percentage: Double
    public let records: [DoseRecord]

    public init(
        date: Date,
        dayNameArabic: String,
        dayShortArabic: String,
        isToday: Bool,
        isFuture: Bool,
        scheduledCount: Int,
        takenCount: Int,
        takenOnTimeCount: Int,
        takenLateCount: Int,
        missedCount: Int,
        percentage: Double,
        records: [DoseRecord]
    ) {
        self.date = date
        self.dayNameArabic = dayNameArabic
        self.dayShortArabic = dayShortArabic
        self.isToday = isToday
        self.isFuture = isFuture
        self.scheduledCount = scheduledCount
        self.takenCount = takenCount
        self.takenOnTimeCount = takenOnTimeCount
        self.takenLateCount = takenLateCount
        self.missedCount = missedCount
        self.percentage = percentage
        self.records = records
    }
}

// MARK: - Medication Specific Adherence Metric
public struct MedicationAdherenceSummary: Identifiable, Equatable {
    public var id: UUID { medicationId }
    public let medicationId: UUID
    public let name: String
    public let dosage: String
    public let scheduledCount: Int
    public let takenCount: Int
    public let missedCount: Int
    public let percentage: Double

    public init(
        medicationId: UUID,
        name: String,
        dosage: String,
        scheduledCount: Int,
        takenCount: Int,
        missedCount: Int,
        percentage: Double
    ) {
        self.medicationId = medicationId
        self.name = name
        self.dosage = dosage
        self.scheduledCount = scheduledCount
        self.takenCount = takenCount
        self.missedCount = missedCount
        self.percentage = percentage
    }
}

// MARK: - Adherence Performance Tier
public enum AdherenceTier {
    case excellent     // >= 90%
    case good          // 75% - 89%
    case fair          // 50% - 74%
    case low           // < 50%

    public var titleArabic: String {
        switch self {
        case .excellent:
            return "ممتاز جداً 🌟"
        case .good:
            return "جيد ومستقر 👍"
        case .fair:
            return "متوسط يحتاج متابعة ⚠️"
        case .low:
            return "منخفض بحاجة للاهتمام ⚠️"
        }
    }

    public var messageArabic: String {
        switch self {
        case .excellent:
            return "التزام رائع بمواعيد الأدوية المحددة بدون تأخير ملحوظ."
        case .good:
            return "التزام جيد بمعظم الجرعات مع بعض التأخيرات البسيطة."
        case .fair:
            return "تم تفويت بعض الجرعات، ينصح بضبط التذكيرات لمزيد من الانضباط."
        case .low:
            return "نسبة تفويت الجرعات مرتفعة، ينصح بمراجعة جدول المواعيد مع مقدم الرعاية."
        }
    }

    public var color: Color {
        switch self {
        case .excellent:
            return Color.dawaiTaken
        case .good:
            return Color.dawaiPrimary
        case .fair:
            return Color.dawaiWarning
        case .low:
            return Color(red: 220.0 / 255.0, green: 53.0 / 255.0, blue: 69.0 / 255.0)
        }
    }
}

// MARK: - Full Weekly Adherence Report (UC-7 Output Model)
public struct WeeklyAdherenceReport: Equatable {
    public let patientId: String
    public let patientDisplayName: String
    public let period: WeekPeriod
    public let totalScheduled: Int
    public let totalTaken: Int
    public let totalTakenOnTime: Int
    public let totalTakenLate: Int
    public let totalMissed: Int
    public let adherencePercentage: Double
    public let dailySummaries: [DailyAdherenceSummary]
    public let medicationSummaries: [MedicationAdherenceSummary]
    public let hasSufficientData: Bool
    public let trendVsPreviousWeek: Double? // e.g. +5.0 or -3.0

    public var tier: AdherenceTier {
        if adherencePercentage >= 90.0 {
            return .excellent
        } else if adherencePercentage >= 75.0 {
            return .good
        } else if adherencePercentage >= 50.0 {
            return .fair
        } else {
            return .low
        }
    }

    public init(
        patientId: String,
        patientDisplayName: String,
        period: WeekPeriod,
        totalScheduled: Int,
        totalTaken: Int,
        totalTakenOnTime: Int,
        totalTakenLate: Int,
        totalMissed: Int,
        adherencePercentage: Double,
        dailySummaries: [DailyAdherenceSummary],
        medicationSummaries: [MedicationAdherenceSummary],
        hasSufficientData: Bool,
        trendVsPreviousWeek: Double? = nil
    ) {
        self.patientId = patientId
        self.patientDisplayName = patientDisplayName
        self.period = period
        self.totalScheduled = totalScheduled
        self.totalTaken = totalTaken
        self.totalTakenOnTime = totalTakenOnTime
        self.totalTakenLate = totalTakenLate
        self.totalMissed = totalMissed
        self.adherencePercentage = adherencePercentage
        self.dailySummaries = dailySummaries
        self.medicationSummaries = medicationSummaries
        self.hasSufficientData = hasSufficientData
        self.trendVsPreviousWeek = trendVsPreviousWeek
    }
}
