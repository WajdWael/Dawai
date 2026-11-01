//
//  HomeMockData.swift
//  Dawai
//
//  Lightweight dummy models and preview data for Patient & Caregiver home views.
//  Designed for easy deletion/replacement once real persistence and backend are wired up.
//

import Foundation

// MARK: - Medication Item Model
public struct MedicationItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var dosage: String
    public var timeString: String
    public var scheduledDate: Date?
    public var days: [String]
    public var frequency: String
    public var duration: String
    public var instructions: String?
    public var imageData: Data?
    public var isTaken: Bool
    public var takenAt: Date?
    public var createdAt: Date
    public var isPendingDeletion: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, dosage, timeString, scheduledDate, days, frequency, duration, instructions, imageData, isTaken, takenAt, createdAt, isPendingDeletion
    }

    public init(
        id: UUID = UUID(),
        name: String,
        dosage: String,
        timeString: String,
        scheduledDate: Date? = nil,
        days: [String] = ["كل يوم"],
        frequency: String = "مرة يوميًا",
        duration: String = "دائم",
        instructions: String? = nil,
        imageData: Data? = nil,
        isTaken: Bool = false,
        takenAt: Date? = nil,
        createdAt: Date = Date(),
        isPendingDeletion: Bool = false
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.timeString = timeString
        self.scheduledDate = scheduledDate
        self.days = days
        self.frequency = frequency
        self.duration = duration
        self.instructions = instructions
        self.imageData = imageData
        self.isTaken = isTaken
        self.takenAt = takenAt
        self.createdAt = createdAt
        self.isPendingDeletion = isPendingDeletion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        dosage = try container.decode(String.self, forKey: .dosage)
        timeString = try container.decode(String.self, forKey: .timeString)
        scheduledDate = try container.decodeIfPresent(Date.self, forKey: .scheduledDate)
        days = try container.decodeIfPresent([String].self, forKey: .days) ?? ["كل يوم"]
        frequency = try container.decodeIfPresent(String.self, forKey: .frequency) ?? "مرة يوميًا"
        duration = try container.decodeIfPresent(String.self, forKey: .duration) ?? "دائم"
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        isTaken = try container.decodeIfPresent(Bool.self, forKey: .isTaken) ?? false
        takenAt = try container.decodeIfPresent(Date.self, forKey: .takenAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isPendingDeletion = try container.decodeIfPresent(Bool.self, forKey: .isPendingDeletion) ?? false
    }
}

// MARK: - Use-Case 11 (UC-11): Medication Deletion Request Model
public struct MedicationDeletionRequest: Identifiable, Codable, Equatable {
    public let id: UUID
    public let medicationId: UUID
    public let medicationName: String
    public let dosage: String
    public let timeString: String
    public let patientId: String
    public let patientDisplayName: String
    public let caregiverId: String?
    public let requestedAt: Date
    public var status: RequestStatus

    public enum RequestStatus: String, Codable {
        case pending
        case approved
        case rejected
    }

    public init(
        id: UUID = UUID(),
        medicationId: UUID,
        medicationName: String,
        dosage: String,
        timeString: String,
        patientId: String,
        patientDisplayName: String,
        caregiverId: String? = nil,
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
        self.caregiverId = caregiverId
        self.requestedAt = requestedAt
        self.status = status
    }
}

// MARK: - Upcoming Dose Model
public struct UpcomingDose: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var timeString: String
    public var dosage: String
    public var isTaken: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        timeString: String,
        dosage: String = "جرعة مجدولة",
        isTaken: Bool = false
    ) {
        self.id = id
        self.name = name
        self.timeString = timeString
        self.dosage = dosage
        self.isTaken = isTaken
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
public struct BeneficiarySummary: Identifiable, Equatable {
    public let id: UUID
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
        UpcomingDose(name: "ميترفين", timeString: "12:00 ص", dosage: "حبة واحدة بعد الأكل", isTaken: false),
        UpcomingDose(name: "فيتامين د", timeString: "10:00 ص", dosage: "قطرة واحدة يوميًا", isTaken: false)
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
            scheduledTime: "11:30 م",
            isInvitation: false,
            delayedMedicationName: "اسبرين",
            delayedDosage: "500 ملغ",
            phoneNumber: "0501234567"
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
