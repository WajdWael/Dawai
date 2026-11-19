//
//  LocalDataStore.swift
//  Dawai
//
//  Versioning, fresh-install detection and full wipe of all locally stored user data.
//

import Foundation
import UserNotifications

@MainActor
public enum LocalDataStore {

    /// Bump this when the shape of any persisted data changes, and add a step to `migrate(from:)`.
    public static let currentSchemaVersion = 2

    private static let schemaVersionKey = "dawai_data_schema_version"

    /// Every UserDefaults key that holds user data. Used both to wipe data and to
    /// recognise installs that existed before the schema version was introduced.
    private static let userDataKeys = [
        UserDefaultsMedicationStore.medicationsKey,
        UserDefaultsMedicationStore.deletionRequestsKey,
        UserDefaultsDoseRecordStore.doseRecordsKey,
        UserDefaultsInvitationStore.invitationsKey,
        UserDefaultsInvitationStore.relationshipsKey
    ]

    private static let legacyAndDemoKeys = [
        "dawai_stored_medications_v1",
        "dawai_stored_dose_records_v1",
        "dawai_demo_mode_enabled"
    ]

    /// Removes all persisted UserDefaults payloads and scheduled/delivered local notifications.
    private static func wipePersistedUserDefaultsAndNotifications() {
        let defaults = UserDefaults.standard
        (userDataKeys + legacyAndDemoKeys).forEach { defaults.removeObject(forKey: $0) }

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        MedicationAlarmService.shared.cancelAllAlarms()
        DoseLiveActivityManager.shared.endAllActivities()
    }

    /// Call once, as early as possible at launch (before any service is first used).
    public static func prepareOnLaunch() {
        let defaults = UserDefaults.standard
        let storedVersion = defaults.object(forKey: schemaVersionKey) as? Int

        guard let storedVersion else {
            let isInstallFromBeforeVersioning = (userDataKeys + legacyAndDemoKeys).contains {
                defaults.object(forKey: $0) != nil
            }

            if !isInstallFromBeforeVersioning {
                // Fresh install. iOS keeps Keychain items after an app is deleted, so an identity
                // from a previous install could survive and skip onboarding. Clear it.
                KeychainService.shared.clearAllCredentials()
            }
            wipePersistedUserDefaultsAndNotifications()
            defaults.set(currentSchemaVersion, forKey: schemaVersionKey)
            return
        }

        if storedVersion < currentSchemaVersion {
            migrate(from: storedVersion)
            defaults.set(currentSchemaVersion, forKey: schemaVersionKey)
        }

        // Guard against orphaned data when no user identity exists (new/reset onboarding state).
        if KeychainService.shared.loadUserIdentity() == nil {
            wipePersistedUserDefaultsAndNotifications()
        }
    }

    /// Migrates older schema versions to `currentSchemaVersion`.
    private static func migrate(from oldVersion: Int) {
        if oldVersion < 2 {
            // One-time clean reset for pre-v2 test installs carrying legacy/demo/seeded artifacts.
            wipePersistedUserDefaultsAndNotifications()
        }
    }

    /// Deletes all user data stored on the device: medications, deletion requests, dose history,
    /// invitations, relationships, pending notifications and the demo-mode flag.
    /// The appearance and notification preferences are kept, and the identity is cleared separately
    /// by `AppState.resetIdentityAndAllData()`.
    public static func resetAllUserData() {
        CloudKitSyncManager.shared.clearPendingQueue()
        MedicationService.shared.resetAllData()
        AdherenceService.shared.resetAllData()
        RelationshipService.shared.resetAllData()
        DemoModeService.shared.clearFlag()
        #if DEBUG
        AppClock.shared.reset()
        #endif

        wipePersistedUserDefaultsAndNotifications()
        UserDefaults.standard.set(currentSchemaVersion, forKey: schemaVersionKey)
    }
}

