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

    // MARK: - Use-Case 12 (UC-12): Today's Medications & Auto-Sorting State
    @Published public private(set) var todayMedications: [MedicationItem] = []
    private var timeProgressionTimer: AnyCancellable?

    // MARK: - Use-Case 11 (UC-11): Collaborative Medication Deletion State
    @Published public private(set) var pendingDeletionRequests: [MedicationDeletionRequest] = []
    private let storageKeyDeletionRequests = "dawai_stored_deletion_requests_v1"

    // Feedback & Toast notifications
    @Published public var toastMessage: String? = nil
    @Published public var notificationWarning: String? = nil

    private let storageKey = "dawai_stored_medications_v2"
    private let maxImageSizeBytes = 5 * 1024 * 1024 // 5 MB (UC-3 S#4)

    public init() {
        loadPersistedMedications()
        loadPersistedDeletionRequests()
        setupTimeProgressionTimer()
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
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([MedicationItem].self, from: data),
           !decoded.isEmpty {
            self.medications = decoded.map { item in
                var m = item
                m.timeString = m.timeString.westernNumerals
                m.dosage = m.dosage.westernNumerals
                return m
            }
        } else {
            // Seed with initial HomeMockData
            let initial = [
                HomeMockData.activeMedication,
                MedicationItem(name: "ميترفين", dosage: "حبة واحدة بعد الأكل", timeString: "12:00 ص", scheduledDate: nil, days: ["كل يوم"], frequency: "مرة يوميًا"),
                MedicationItem(name: "فيتامين د", dosage: "قطرة واحدة يوميًا", timeString: "10:00 ص", scheduledDate: nil, days: ["كل يوم"], frequency: "مرة يوميًا")
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

    // MARK: - UC-11 Deletion Requests Persistence
    public func loadPersistedDeletionRequests() {
        if let data = UserDefaults.standard.data(forKey: storageKeyDeletionRequests),
           let decoded = try? JSONDecoder().decode([MedicationDeletionRequest].self, from: data) {
            self.pendingDeletionRequests = decoded
        }
    }

    private func persistDeletionRequests() {
        if let encoded = try? JSONEncoder().encode(pendingDeletionRequests) {
            UserDefaults.standard.set(encoded, forKey: storageKeyDeletionRequests)
        }
    }

    // MARK: - UC-12 S#1, S#2, S#3: Automatically Sort & Prioritize by Scheduled Time
    public func refreshDerivedState() {
        let now = Date()
        let nowComps = Calendar.current.dateComponents([.hour, .minute], from: now)
        let currentMinutes = (nowComps.hour ?? 0) * 60 + (nowComps.minute ?? 0)

        // 1. UC-12 S#1: Retrieve registered medications scheduled for the current day
        let todaysList = medications.filter { isScheduledForToday($0, on: now) }

        // 2. UC-12 S#2: Automatically sort daily medications according to their scheduled times
        let sortedTodaysList = todaysList.sorted { a, b in
            scheduledMinutes(for: a) < scheduledMinutes(for: b)
        }
        self.todayMedications = sortedTodaysList

        // 3. UC-12 S#2: Prioritize the medication whose scheduled time is due or closest to the current time
        let untaken = sortedTodaysList.filter { !$0.isTaken }

        if !untaken.isEmpty {
            // If any untaken doses are due/overdue (scheduled time <= current time):
            // Prioritize the due medication closest to current time
            let dueDoses = untaken.filter { scheduledMinutes(for: $0) <= currentMinutes }
            let upcomingDosesList = untaken.filter { scheduledMinutes(for: $0) > currentMinutes }

            if !dueDoses.isEmpty {
                // The dose due that is closest to now (or most recent due)
                self.activeMedication = dueDoses.max(by: { scheduledMinutes(for: $0) < scheduledMinutes(for: $1) }) ?? dueDoses.first
            } else {
                // All untaken doses are upcoming in the future today; pick the one closest to current time
                self.activeMedication = upcomingDosesList.min(by: { scheduledMinutes(for: $0) < scheduledMinutes(for: $1) }) ?? untaken.first
            }
        } else {
            // All doses for today are taken: select first in schedule
            self.activeMedication = sortedTodaysList.first
        }

        // 4. Generate schedule doses for other medications (excluding the active highlighted card)
        let otherMeds = sortedTodaysList.filter { $0.id != self.activeMedication?.id }
        self.upcomingDoses = otherMeds.map { item in
            UpcomingDose(
                id: item.id,
                name: item.name,
                timeString: item.timeString.westernNumerals,
                dosage: item.dosage.westernNumerals,
                isTaken: item.isTaken
            )
        }

        // 5. Count untaken doses for today
        self.remainingDoses = untaken.count
    }

    // MARK: - Use-Case 5 (UC-5): Missed Dose Calculations (30-Minute Grace Period)
    /// UC-5 S#1: Determines if a scheduled dose has remained unconfirmed for 30 minutes after its scheduled time
    public func isDoseMissed(_ item: MedicationItem, at date: Date = Date()) -> Bool {
        guard isScheduledForToday(item, on: date) && !item.isTaken else { return false }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let currentMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let medMinutes = scheduledMinutes(for: item)
        // 30-minute grace period
        return currentMinutes >= (medMinutes + 30)
    }

    /// List of medications scheduled for today whose 30-minute grace period has passed without confirmation
    public var missedMedicationsToday: [MedicationItem] {
        let now = Date()
        return todayMedications.filter { isDoseMissed($0, at: now) }
    }

    /// True when any scheduled medication has remained unconfirmed 30 minutes past its due time
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

        // 3. Authorization check for Caregiver (UC-3 Alternate Course S#8)
        if currentUser.role == .caregiver {
            try validateCaregiverPermission(caregiverId: currentUser.id, targetPatientId: targetPatientId)
        }

        // 4. Prevent duplicate medication record with same name and time
        let duplicate = medications.contains { existing in
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
        medications.insert(cleanItem, at: 0)
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

        if let user = currentUser, user.role == .caregiver {
            try validateCaregiverPermission(caregiverId: user.id, targetPatientId: targetPatientId)
        }

        guard let index = medications.firstIndex(where: { $0.id == cleanItem.id }) else {
            throw MedicationError.saveFailed
        }

        medications[index] = cleanItem
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
        if let item = medications.first(where: { $0.id == id }) {
            // UC-11 S#5: Cancel future scheduled reminders
            cancelReminder(id: id)
            // UC-11 S#4: Remove medication from active medication list and update system database
            medications.removeAll(where: { $0.id == id })
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
        guard let item = medications.first(where: { $0.id == id }) else { return }
        // UC-11 S#5: Cancels the medication's future scheduled reminders
        cancelReminder(id: id)
        // UC-11 S#4: Removes the medication from active medication list
        medications.removeAll(where: { $0.id == id })
        pendingDeletionRequests.removeAll(where: { $0.medicationId == id })
        persistMedications()
        persistDeletionRequests()
        // UC-11 S#6: Refreshes medication list and Home Page
        refreshDerivedState()

        let target = patientName != nil ? " من جدول \(patientName!)" : ""
        showToast("تم حذف دواء \"\(item.name)\"\(target) نهائياً وإلغاء جميع التذكيرات.")
    }

    /// UC-11 Collaborative Workflow: Patient requests deletion of a medication
    /// If connected to caregivers: marks medication as pending deletion and sends a request/notification to caregiver.
    /// If not connected to any caregiver: deletes directly.
    public func requestMedicationDeletionByPatient(
        medicationId: UUID,
        patient: UserIdentity,
        caregivers: [ActiveRelationship]
    ) {
        guard let item = medications.first(where: { $0.id == medicationId }) else { return }

        // If no caregiver is connected, delete directly
        if caregivers.isEmpty {
            deleteMedicationDirectly(id: medicationId)
            return
        }

        // Mark medication as pending deletion
        if let index = medications.firstIndex(where: { $0.id == medicationId }) {
            medications[index].isPendingDeletion = true
            persistMedications()
            refreshDerivedState()
        }

        let caregiverId = caregivers.first?.caregiverId
        let request = MedicationDeletionRequest(
            medicationId: medicationId,
            medicationName: item.name,
            dosage: item.dosage,
            timeString: item.timeString,
            patientId: patient.id,
            patientDisplayName: patient.displayName,
            caregiverId: caregiverId
        )

        if !pendingDeletionRequests.contains(where: { $0.medicationId == medicationId }) {
            pendingDeletionRequests.append(request)
            persistDeletionRequests()
        }

        showToast("تم إرسال طلب حذف دواء \"\(item.name)\" إلى مقدم الرعاية للموافقة.")
    }

    /// UC-11: Caregiver approves deletion request -> permanently deletes medication from patient's schedule
    public func approveDeletionRequest(requestId: UUID) {
        guard let reqIndex = pendingDeletionRequests.firstIndex(where: { $0.id == requestId }) else { return }
        let request = pendingDeletionRequests[reqIndex]

        // 1. Cancel future reminders (UC-11 S#5)
        cancelReminder(id: request.medicationId)

        // 2. Remove medication permanently (UC-11 S#4)
        medications.removeAll(where: { $0.id == request.medicationId })

        // 3. Remove request
        pendingDeletionRequests.remove(at: reqIndex)

        // 4. Persist and refresh (UC-11 S#6)
        persistMedications()
        persistDeletionRequests()
        refreshDerivedState()

        showToast("تمت الموافقة على حذف دواء \"\(request.medicationName)\" وحذفه نهائياً.")
    }

    /// UC-11: Caregiver rejects deletion request -> keeps medication active in patient's schedule
    public func rejectDeletionRequest(requestId: UUID) {
        guard let reqIndex = pendingDeletionRequests.firstIndex(where: { $0.id == requestId }) else { return }
        let request = pendingDeletionRequests[reqIndex]

        // 1. Restore medication (clear pending flag, keep active in schedule)
        if let medIndex = medications.firstIndex(where: { $0.id == request.medicationId }) {
            medications[medIndex].isPendingDeletion = false
            persistMedications()
            refreshDerivedState()
        }

        // 2. Remove request
        pendingDeletionRequests.remove(at: reqIndex)
        persistDeletionRequests()

        showToast("تم رفض حذف دواء \"\(request.medicationName)\" والاحتفاظ به في جدول المستفيد.")
    }

    // MARK: - Toggle Taken Status & UC-6 Confirm Dose
    public func toggleTaken(id: UUID) {
        guard let index = medications.firstIndex(where: { $0.id == id }) else { return }
        medications[index].isTaken.toggle()
        if medications[index].isTaken {
            medications[index].takenAt = Date()
            cancelMissedDoseAlert(id: id)
            AdherenceService.shared.recordDoseTaken(
                medication: medications[index],
                patientId: "default_patient",
                takenAt: Date()
            )
        } else {
            medications[index].takenAt = nil
        }
        persistMedications()
        refreshDerivedState()
    }

    /// UC-6: Confirms dose taken, records timestamp, updates status and notifies caregivers
    public func confirmDoseTaken(id: UUID, patient: UserIdentity) {
        guard let index = medications.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        medications[index].isTaken = true
        medications[index].takenAt = now
        persistMedications()
        refreshDerivedState()

        // UC-7: Record in dose log for weekly adherence report
        AdherenceService.shared.recordDoseTaken(
            medication: medications[index],
            patientId: patient.id,
            takenAt: now
        )

        // UC-5: Dose confirmed -> cancel caregiver missed dose alert
        cancelMissedDoseAlert(id: id)

        // UC-6 S#6: Notify connected caregivers
        RelationshipService.shared.notifyCaregiversDoseTaken(
            medicationName: medications[index].name,
            patientName: patient.displayName
        )

        showToast("تم تأكيد أخذ جرعة \"\(medications[index].name)\" بنجاح.")
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
            let missedContent = UNMutableNotificationContent()
            missedContent.title = "تنبيه تأخر جرعة: \(item.name)"
            missedContent.body = "لم يتم تأكيد أخذ جرعة \(item.name) (\(item.dosage)) بعد مرور 30 دقيقة من موعدها."
            missedContent.sound = .default
            missedContent.userInfo = [
                "medicationId": item.id.uuidString,
                "medicationName": item.name,
                "dosage": item.dosage,
                "type": "missed_dose_alert"
            ]

            var missedComps = DateComponents()
            let schedMinutes = scheduledMinutes(for: item)
            let alertMinutes = (schedMinutes + 30) % 1440
            missedComps.hour = alertMinutes / 60
            missedComps.minute = alertMinutes % 60

            let missedTrigger = UNCalendarNotificationTrigger(dateMatching: missedComps, repeats: true)
            let missedRequest = UNNotificationRequest(
                identifier: "medication_missed_dose_\(item.id.uuidString)",
                content: missedContent,
                trigger: missedTrigger
            )
            try? await center.add(missedRequest)

            return true
        } catch {
            return false
        }
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
        content.body = "لم يتم تأكيد أخذ جرعة \(item.name) (\(item.dosage)) بعد مرور 30 دقيقة من موعدها."
        content.sound = .default
        content.userInfo = [
            "medicationId": item.id.uuidString,
            "medicationName": item.name,
            "dosage": item.dosage,
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
            for med in medications where !med.isTaken {
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
            let beneficiary = BeneficiarySummary(
                id: UUID(),
                name: "الوالد",
                hasDelayAlert: true,
                delayNotice: "30 د تأخير، \(medName)",
                scheduledTime: nil,
                isInvitation: false,
                delayedMedicationName: medName,
                delayedDosage: dosage,
                phoneNumber: "0501234567"
            )
            Task { @MainActor in
                self.appState?.openCaregiverPatientDetail(for: beneficiary)
            }
        } else if let medIdString = userInfo["medicationId"] as? String,
                  let medId = UUID(uuidString: medIdString) {
            Task { @MainActor in
                self.appState?.openDoseConfirmation(for: medId)
            }
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
