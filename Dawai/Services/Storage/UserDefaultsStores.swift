//
//  UserDefaultsStores.swift
//  Dawai
//
//  Local, on-device implementations of the store protocols, backed by UserDefaults + JSON.
//  The storage keys are unchanged from earlier versions, so existing data keeps loading.
//

import Foundation

// MARK: - Medications & Deletion Requests
public final class UserDefaultsMedicationStore: MedicationStore {
    public static let medicationsKey = "dawai_stored_medications_v2"
    public static let deletionRequestsKey = "dawai_stored_deletion_requests_v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadMedications(legacyPatientId: String) -> [MedicationItem] {
        let decoder = JSONDecoder()
        decoder.userInfo[MedicationItem.legacyPatientIdUserInfoKey] = legacyPatientId
        return defaults.decodedArray([MedicationItem].self, forKey: Self.medicationsKey, decoder: decoder) ?? []
    }

    public func saveMedications(_ medications: [MedicationItem]) {
        defaults.setEncoded(medications, forKey: Self.medicationsKey)
    }

    public func loadDeletionRequests() -> [MedicationDeletionRequest] {
        defaults.decodedArray([MedicationDeletionRequest].self, forKey: Self.deletionRequestsKey) ?? []
    }

    public func saveDeletionRequests(_ requests: [MedicationDeletionRequest]) {
        defaults.setEncoded(requests, forKey: Self.deletionRequestsKey)
    }

    public func removeAll() {
        defaults.removeObject(forKey: Self.medicationsKey)
        defaults.removeObject(forKey: Self.deletionRequestsKey)
    }
}

// MARK: - Dose Records
public final class UserDefaultsDoseRecordStore: DoseRecordStore {
    public static let doseRecordsKey = "dawai_stored_dose_records_v2"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadDoseRecords() -> [DoseRecord] {
        defaults.decodedArray([DoseRecord].self, forKey: Self.doseRecordsKey) ?? []
    }

    public func saveDoseRecords(_ records: [DoseRecord]) {
        defaults.setEncoded(records, forKey: Self.doseRecordsKey)
    }

    public func removeAll() {
        defaults.removeObject(forKey: Self.doseRecordsKey)
    }
}

// MARK: - Invitations & Relationships
public final class UserDefaultsInvitationStore: InvitationStore {
    public static let invitationsKey = "dawai_stored_invitations_v1"
    public static let relationshipsKey = "dawai_stored_relationships_v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadInvitations() -> [ConnectionInvitation] {
        defaults.decodedArray([ConnectionInvitation].self, forKey: Self.invitationsKey) ?? []
    }

    public func saveInvitations(_ invitations: [ConnectionInvitation]) {
        defaults.setEncoded(invitations, forKey: Self.invitationsKey)
    }

    public func loadRelationships() -> [ActiveRelationship] {
        defaults.decodedArray([ActiveRelationship].self, forKey: Self.relationshipsKey) ?? []
    }

    public func saveRelationships(_ relationships: [ActiveRelationship]) {
        defaults.setEncoded(relationships, forKey: Self.relationshipsKey)
    }

    public func removeAll() {
        defaults.removeObject(forKey: Self.invitationsKey)
        defaults.removeObject(forKey: Self.relationshipsKey)
    }
}

// MARK: - JSON Helpers
private extension UserDefaults {
    /// Decodes the JSON array stored under `key`. Returns `nil` if nothing is stored or it cannot be decoded.
    func decodedArray<T: Decodable>(_ type: [T].Type, forKey key: String, decoder: JSONDecoder = JSONDecoder()) -> [T]? {
        guard let data = data(forKey: key) else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            print("Failed to decode stored data for \(key): \(error)")
            return nil
        }
    }

    func setEncoded<T: Encodable>(_ value: T, forKey key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            set(data, forKey: key)
        } catch {
            print("Failed to persist data for \(key): \(error)")
        }
    }
}
