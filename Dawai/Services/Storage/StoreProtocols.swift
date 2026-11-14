//
//  StoreProtocols.swift
//  Dawai
//
//  Persistence boundaries for the app's services. Services depend only on these protocols,
//  so the UserDefaults implementations can later be replaced (for example by CloudKit-backed
//  stores) without changing service or view code.
//

import Foundation

/// Stores medications and the patient deletion requests that refer to them. Used by `MedicationService`.
public protocol MedicationStore: AnyObject {
    /// Returns every stored medication for every patient on this device, or `[]` if none can be read.
    /// - Parameter legacyPatientId: Owner assigned to medications that were saved before `patientId` existed.
    func loadMedications(legacyPatientId: String) -> [MedicationItem]
    func saveMedications(_ medications: [MedicationItem])

    /// Returns every stored deletion request, or `[]` if none can be read.
    func loadDeletionRequests() -> [MedicationDeletionRequest]
    func saveDeletionRequests(_ requests: [MedicationDeletionRequest])

    /// Deletes all medications and deletion requests.
    func removeAll()
}

/// Stores the dose log used for adherence reports. Used by `AdherenceService`.
public protocol DoseRecordStore: AnyObject {
    /// Returns every stored dose record, or `[]` if none can be read.
    func loadDoseRecords() -> [DoseRecord]
    func saveDoseRecords(_ records: [DoseRecord])

    /// Deletes all dose records.
    func removeAll()
}

/// Stores linking invitations and the active patient–caregiver relationships they create.
/// Used by `RelationshipService`.
public protocol InvitationStore: AnyObject {
    /// Returns every stored invitation (outgoing and incoming), or `[]` if none can be read.
    func loadInvitations() -> [ConnectionInvitation]
    func saveInvitations(_ invitations: [ConnectionInvitation])

    /// Returns every stored relationship, or `[]` if none can be read.
    func loadRelationships() -> [ActiveRelationship]
    func saveRelationships(_ relationships: [ActiveRelationship])

    /// Deletes all invitations and relationships.
    func removeAll()
}
