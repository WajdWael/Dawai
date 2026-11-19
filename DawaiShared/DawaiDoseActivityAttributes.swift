//
//  DawaiDoseActivityAttributes.swift
//  DawaiShared
//
//  Shared ActivityKit attributes used by both the main Dawai app and the DawaiWidgets
//  Live Activity / Dynamic Island extension.
//

import ActivityKit
import Foundation

public struct DawaiDoseActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var medicationId: String
        public var medicationName: String
        public var dosage: String
        public var timeString: String
        public var slotMinutes: Int
        public var scheduledDate: Date
        /// `"upcoming"` | `"due"` | `"late"`
        public var phase: String
        public var remainingDosesCount: Int

        public init(
            medicationId: String,
            medicationName: String,
            dosage: String,
            timeString: String,
            slotMinutes: Int,
            scheduledDate: Date,
            phase: String,
            remainingDosesCount: Int
        ) {
            self.medicationId = medicationId
            self.medicationName = medicationName
            self.dosage = dosage
            self.timeString = timeString
            self.slotMinutes = slotMinutes
            self.scheduledDate = scheduledDate
            self.phase = phase
            self.remainingDosesCount = remainingDosesCount
        }

        public var confirmDoseURL: URL {
            var components = URLComponents()
            components.scheme = "dawai"
            components.host = "confirm-dose"
            components.queryItems = [
                URLQueryItem(name: "medicationId", value: medicationId),
                URLQueryItem(name: "slotMinutes", value: String(slotMinutes))
            ]
            return components.url ?? URL(string: "dawai://confirm-dose")!
        }

        public var isLate: Bool { phase == "late" }
        public var isDue: Bool { phase == "due" }
        public var isUpcoming: Bool { phase == "upcoming" }
    }

    public var patientName: String

    public init(patientName: String) {
        self.patientName = patientName
    }
}
