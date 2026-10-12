//
//  HomeMockData.swift
//  Dawai
//
//  Lightweight dummy models and preview data for Patient & Caregiver home views.
//  Designed for easy deletion/replacement once real persistence and backend are wired up.
//

import Foundation

// MARK: - Medication Item Model
public struct MedicationItem: Identifiable {
    public let id: UUID
    public var name: String
    public var dosage: String
    public var timeString: String
    public var isTaken: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        dosage: String,
        timeString: String,
        isTaken: Bool = false
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.timeString = timeString
        self.isTaken = isTaken
    }
}

// MARK: - Upcoming Dose Model
public struct UpcomingDose: Identifiable {
    public let id: UUID
    public var name: String
    public var timeString: String

    public init(
        id: UUID = UUID(),
        name: String,
        timeString: String
    ) {
        self.id = id
        self.name = name
        self.timeString = timeString
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
public struct BeneficiarySummary: Identifiable {
    public let id: UUID
    public var name: String
    public var hasDelayAlert: Bool
    public var delayNotice: String?
    public var scheduledTime: String?
    public var isInvitation: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        hasDelayAlert: Bool = false,
        delayNotice: String? = nil,
        scheduledTime: String? = nil,
        isInvitation: Bool = false
    ) {
        self.id = id
        self.name = name
        self.hasDelayAlert = hasDelayAlert
        self.delayNotice = delayNotice
        self.scheduledTime = scheduledTime
        self.isInvitation = isInvitation
    }
}

// MARK: - Centralized Dummy Data Store
public enum HomeMockData {
    // Patient Data
    public static let patientRemainingDoses: Int = 3

    public static let activeMedication = MedicationItem(
        name: "اسبرين",
        dosage: "حبتان قبل الاكل",
        timeString: "الساعة 12:00 ص",
        isTaken: false
    )

    public static let upcomingDoses: [UpcomingDose] = [
        UpcomingDose(name: "ميترفين", timeString: "12:00 ص"),
        UpcomingDose(name: "اسبرين", timeString: "12:00 ص")
    ]

    public static let patientCaregivers: [CaregiverLink] = [
        CaregiverLink(name: "سارة", statusText: "تم ارسال الدعوة في انتظار القبول", isPending: true)
    ]

    // Caregiver Data
    public static let beneficiaries: [BeneficiarySummary] = [
        BeneficiarySummary(
            name: "عمر",
            hasDelayAlert: true,
            delayNotice: "30 د تأخير، اسبرين (500 ملغ)",
            scheduledTime: "11:30 PM",
            isInvitation: false
        ),
        BeneficiarySummary(
            name: "خلود",
            hasDelayAlert: false,
            delayNotice: nil,
            scheduledTime: nil,
            isInvitation: false
        ),
        BeneficiarySummary(
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
