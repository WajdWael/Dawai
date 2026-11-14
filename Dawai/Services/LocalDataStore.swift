//
//  LocalDataStore.swift
//  Dawai
//
//  Versioning, fresh-install detection and full wipe of all locally stored user data.
//

import Foundation
import UserNotifications

public enum LocalDataStore {

    /// Bump this when the shape of any persisted data changes, and add a step to `migrate(from:)`.
    public static let currentSchemaVersion = 1

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

    /// Call once, as early as possible at launch (before any service is first used).
    public static func prepareOnLaunch() {
        let defaults = UserDefaults.standard
        let storedVersion = defaults.object(forKey: schemaVersionKey) as? Int

        guard let storedVersion else {
            let isInstallFromBeforeVersioning = userDataKeys.contains { defaults.object(forKey: $0) != nil }

            if !isInstallFromBeforeVersioning {
                // Fresh install. iOS keeps Keychain items after an app is deleted, so an identity
                // from a previous install could survive and skip onboarding. Clear it.
                KeychainService.shared.clearAllCredentials()
            }
            // Installs from before versioning are only stamped, never wiped.
            defaults.set(currentSchemaVersion, forKey: schemaVersionKey)
            return
        }

        if storedVersion < currentSchemaVersion {
            migrate(from: storedVersion)
            defaults.set(currentSchemaVersion, forKey: schemaVersionKey)
        }
    }

    /// Placeholder for future data migrations. Nothing to migrate at version 1.
    private static func migrate(from oldVersion: Int) {
        // Example for a future change:
        // if oldVersion < 2 { /* convert stored medications to the new format */ }
    }

    /// Deletes all user data stored on the device: medications, deletion requests, dose history,
    /// invitations, relationships, pending notifications and the demo-mode flag.
    /// The appearance and notification preferences are kept, and the identity is cleared separately
    /// by `AppState.resetIdentityAndAllData()`.
    public static func resetAllUserData() {
        MedicationService.shared.resetAllData()
        AdherenceService.shared.resetAllData()
        RelationshipService.shared.resetAllData()
        DemoModeService.shared.clearFlag()

        let defaults = UserDefaults.standard
        userDataKeys.forEach { defaults.removeObject(forKey: $0) }
        defaults.set(currentSchemaVersion, forKey: schemaVersionKey)

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}

