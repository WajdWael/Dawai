//
//  MedicationAlarmService.swift
//  Dawai
//
//  Medication alarm & alert service.
//  Uses high-priority local notifications and system alert sounds to ensure the user never misses a dose.
//

import Foundation
import SwiftUI
import UserNotifications

@MainActor
public final class MedicationAlarmService {
    public static let shared = MedicationAlarmService()

    public static let alarmKitEnabledKey = "dawai_alarmkit_enabled"
    private static let storedAlarmIDsKey = "dawai_alarmkit_ids_v1"

    public var isUserEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: Self.alarmKitEnabledKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.alarmKitEnabledKey)
        }
    }

    public var isSupportedOnDevice: Bool {
        true
    }

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private init() {}

    // MARK: - Authorization

    public func requestAuthorizationIfNeeded() async -> Bool {
        guard !isRunningTests, isUserEnabled else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    // MARK: - Schedule / Cancel

    /// Schedules medication reminders and alerts for all dose times of `item`.
    public func scheduleAlarms(for item: MedicationItem, using medicationService: MedicationService) async -> Bool {
        guard !isRunningTests, isUserEnabled else {
            cancelAlarms(forMedicationId: item.id)
            return false
        }

        let notificationsEnabled = UserDefaults.standard.object(forKey: "dawai_notifications_enabled") as? Bool ?? true
        guard notificationsEnabled else {
            cancelAlarms(forMedicationId: item.id)
            return false
        }

        cancelAlarms(forMedicationId: item.id)

        let plans = medicationService.plannedReminders(for: item)
        guard !plans.isEmpty else { return false }

        var scheduledIDs: [UUID] = []
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        for plan in plans {
            let alarmID = UUID()
            let content = UNMutableNotificationContent()
            content.title = "موعد الدواء: \(item.name)"
            content.body = "الجرعة: \(item.dosage) - حان موعد أخذ الدواء الآن"
            if #available(iOS 15.0, *) {
                content.interruptionLevel = .timeSensitive
                content.relevanceScore = 1.0
            }
            if #available(iOS 12.0, *), settings.criticalAlertSetting == .enabled {
                content.sound = .defaultCriticalSound(withAudioVolume: 1.0)
            } else {
                content.sound = .default
            }
            content.categoryIdentifier = MedicationService.doseReminderCategoryIdentifier
            content.userInfo = [
                "medicationId": item.id.uuidString,
                "slotMinutes": plan.slotMinutes,
                "type": "dose_reminder"
            ]

            var dateComponents = DateComponents()
            dateComponents.hour = plan.hour
            dateComponents.minute = plan.minute
            if let wd = plan.weekday {
                dateComponents.weekday = wd
            }
            if let y = plan.year, let m = plan.month, let d = plan.day {
                dateComponents.year = y
                dateComponents.month = m
                dateComponents.day = d
            }

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: plan.repeats)
            let request = UNNotificationRequest(identifier: alarmID.uuidString, content: content, trigger: trigger)

            do {
                try await center.add(request)
                scheduledIDs.append(alarmID)
            } catch {
                continue
            }
        }

        if !scheduledIDs.isEmpty {
            saveAlarmIDs(scheduledIDs, forMedicationId: item.id)
            return true
        }
        return false
    }

    public func cancelAlarms(forMedicationId medicationId: UUID) {
        let existingIDs = loadAlarmIDs(forMedicationId: medicationId)
        removeStoredAlarmIDs(forMedicationId: medicationId)

        guard !isRunningTests, !existingIDs.isEmpty else { return }
        let ids = existingIDs.map(\.uuidString)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    public func cancelAllAlarms() {
        let map = loadAllAlarmIDMaps()
        UserDefaults.standard.removeObject(forKey: Self.storedAlarmIDsKey)

        guard !isRunningTests else { return }
        var allIDs: [String] = []
        for ids in map.values {
            allIDs.append(contentsOf: ids)
        }
        if !allIDs.isEmpty {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: allIDs)
        }
    }

    // MARK: - Persistence for Scheduled Alarm UUIDs

    private func loadAllAlarmIDMaps() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: Self.storedAlarmIDsKey) as? [String: [String]] ?? [:]
    }

    private func loadAlarmIDs(forMedicationId medicationId: UUID) -> [UUID] {
        let map = loadAllAlarmIDMaps()
        return (map[medicationId.uuidString] ?? []).compactMap(UUID.init(uuidString:))
    }

    private func saveAlarmIDs(_ ids: [UUID], forMedicationId medicationId: UUID) {
        var map = loadAllAlarmIDMaps()
        map[medicationId.uuidString] = ids.map(\.uuidString)
        UserDefaults.standard.set(map, forKey: Self.storedAlarmIDsKey)
    }

    private func removeStoredAlarmIDs(forMedicationId medicationId: UUID) {
        var map = loadAllAlarmIDMaps()
        map.removeValue(forKey: medicationId.uuidString)
        UserDefaults.standard.set(map, forKey: Self.storedAlarmIDsKey)
    }
}
