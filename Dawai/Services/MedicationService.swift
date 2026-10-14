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
    @Published public private(set) var medications: [MedicationItem] = []
    @Published public var activeMedication: MedicationItem?
    @Published public var upcomingDoses: [UpcomingDose] = []
    @Published public var remainingDoses: Int = 3

    // Feedback & Toast notifications
    @Published public var toastMessage: String? = nil
    @Published public var notificationWarning: String? = nil

    private let storageKey = "dawai_stored_medications_v2"
    private let maxImageSizeBytes = 5 * 1024 * 1024 // 5 MB (UC-3 S#4)

    public init() {
        loadPersistedMedications()
    }

    // MARK: - Persistence & Initial State
    public func loadPersistedMedications() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([MedicationItem].self, from: data),
           !decoded.isEmpty {
            self.medications = decoded
        } else {
            // Seed with initial HomeMockData
            let initial = [
                HomeMockData.activeMedication,
                MedicationItem(name: "ميترفين", dosage: "حبة واحدة بعد الأكل", timeString: "12:00 ص", scheduledDate: nil, days: ["كل يوم"], frequency: "مرة يوميًا"),
                MedicationItem(name: "اسبرين", dosage: "حبتان قبل الأكل", timeString: "12:00 ص", scheduledDate: nil, days: ["كل يوم"], frequency: "مرة يوميًا")
            ]
            self.medications = initial
            persistMedications()
        }
        refreshDerivedState()
    }

    private func persistMedications() {
        if let encoded = try? JSONEncoder().encode(medications) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func refreshDerivedState() {
        if let first = medications.first(where: { !$0.isTaken }) ?? medications.first {
            self.activeMedication = first
        } else {
            self.activeMedication = nil
        }

        // Generate upcoming doses
        self.upcomingDoses = medications.dropFirst().map { item in
            UpcomingDose(
                id: item.id,
                name: item.name,
                timeString: item.timeString,
                dosage: item.dosage,
                isTaken: item.isTaken
            )
        }

        // Count untaken doses
        let untaken = medications.filter { !$0.isTaken }.count
        self.remainingDoses = untaken
    }

    // MARK: - UC-3 S#2 & S#4: Add Medication
    public func addMedication(
        item: MedicationItem,
        currentUser: UserIdentity,
        targetPatientId: String? = nil
    ) async throws {
        // 1. Validation: Required fields (UC-3 Alternate Course S#1)
        try validateRequiredFields(name: item.name, dosage: item.dosage, timeString: item.timeString)

        // 2. Validation: Image size (UC-3 Alternate Course S#4)
        if let imgData = item.imageData {
            try validateImageData(imgData)
        }

        // 3. Authorization check for Caregiver (UC-3 Alternate Course S#8)
        if currentUser.role == .caregiver {
            try validateCaregiverPermission(caregiverId: currentUser.id, targetPatientId: targetPatientId)
        }

        // 4. Prevent duplicate medication record with same name and time
        let duplicate = medications.contains { existing in
            existing.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ==
                item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() &&
            existing.timeString == item.timeString
        }
        if duplicate {
            // Avoid duplicate additions
            showToast("الدواء مسجل بالفعل بنفس الموعد.")
            return
        }

        // 5. Save to database / local store (UC-3 S#5)
        medications.insert(item, at: 0)
        persistMedications()
        refreshDerivedState()

        // 6. Schedule Notification Reminder (UC-3 S#6 & Alternate Course S#9)
        let scheduled = await scheduleReminder(for: item)
        if !scheduled {
            self.notificationWarning = "تم حفظ الدواء بنجاح، ولكن تعذر تفعيل التذكيرات (يرجى التحقق من أذونات الإشعارات في الإعدادات)."
        }

        // 7. Success confirmation message (UC-3 S#8)
        showToast("تمت إضافة دواء \"\(item.name)\" بنجاح وجدولة التذكيرات!")
    }

    // MARK: - Update Existing Medication (Edit Mode)
    public func updateMedication(
        item: MedicationItem,
        currentUser: UserIdentity? = nil,
        targetPatientId: String? = nil
    ) async throws {
        // 1. Validation
        try validateRequiredFields(name: item.name, dosage: item.dosage, timeString: item.timeString)

        if let imgData = item.imageData {
            try validateImageData(imgData)
        }

        if let user = currentUser, user.role == .caregiver {
            try validateCaregiverPermission(caregiverId: user.id, targetPatientId: targetPatientId)
        }

        guard let index = medications.firstIndex(where: { $0.id == item.id }) else {
            throw MedicationError.saveFailed
        }

        medications[index] = item
        persistMedications()
        refreshDerivedState()

        // Reschedule reminder
        _ = await scheduleReminder(for: item)

        showToast("تم حفظ تعديلات دواء \"\(item.name)\" بنجاح.")
    }

    // MARK: - Delete Medication
    public func deleteMedication(id: UUID) {
        if let item = medications.first(where: { $0.id == id }) {
            cancelReminder(id: id)
            medications.removeAll(where: { $0.id == id })
            persistMedications()
            refreshDerivedState()
            showToast("تم حذف دواء \"\(item.name)\" بنجاح.")
        }
    }

    // MARK: - Toggle Taken Status
    public func toggleTaken(id: UUID) {
        guard let index = medications.firstIndex(where: { $0.id == id }) else { return }
        medications[index].isTaken.toggle()
        persistMedications()
        refreshDerivedState()
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

    private func validateCaregiverPermission(caregiverId: String, targetPatientId: String?) throws {
        let activeRels = RelationshipService.shared.activeRelationships
        let hasActiveConnection = activeRels.contains { rel in
            rel.caregiverId == caregiverId && rel.isActive &&
            (targetPatientId == nil || rel.patientId == targetPatientId)
        }

        if !hasActiveConnection {
            throw MedicationError.unauthorizedCaregiver
        }
    }

    // MARK: - UC-3 S#6 & S#9: Notification Scheduling
    public func scheduleReminder(for item: MedicationItem) async -> Bool {
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

            // Create notification content
            let content = UNMutableNotificationContent()
            content.title = "تذكير بموعد دواء: \(item.name)"
            content.body = "حان موعد تناول الجرعة (\(item.dosage)) - \(item.timeString)"
            if let instructions = item.instructions, !instructions.isEmpty {
                content.body += "\nتعليمات: \(instructions)"
            }
            content.sound = .default

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
            return true
        } catch {
            return false
        }
    }

    public func cancelReminder(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["medication_reminder_\(id.uuidString)"]
        )
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
