//
//  InMemoryTestStores.swift
//  DawaiTests
//

import Foundation
@testable import Dawai

final class InMemoryMedicationStore: MedicationStore {
    var medications: [MedicationItem] = []
    var deletionRequests: [MedicationDeletionRequest] = []

    func loadMedications(legacyPatientId: String) -> [MedicationItem] {
        medications
    }

    func saveMedications(_ medications: [MedicationItem]) {
        self.medications = medications
    }

    func loadDeletionRequests() -> [MedicationDeletionRequest] {
        deletionRequests
    }

    func saveDeletionRequests(_ requests: [MedicationDeletionRequest]) {
        self.deletionRequests = requests
    }

    func removeAll() {
        medications.removeAll()
        deletionRequests.removeAll()
    }
}

final class InMemoryDoseRecordStore: DoseRecordStore {
    var records: [DoseRecord] = []

    func loadDoseRecords() -> [DoseRecord] {
        records
    }

    func saveDoseRecords(_ records: [DoseRecord]) {
        self.records = records
    }

    func removeAll() {
        records.removeAll()
    }
}

final class InMemoryInvitationStore: InvitationStore {
    var invitations: [ConnectionInvitation] = []
    var relationships: [ActiveRelationship] = []

    func loadInvitations() -> [ConnectionInvitation] {
        invitations
    }

    func saveInvitations(_ invitations: [ConnectionInvitation]) {
        self.invitations = invitations
    }

    func loadRelationships() -> [ActiveRelationship] {
        relationships
    }

    func saveRelationships(_ relationships: [ActiveRelationship]) {
        self.relationships = relationships
    }

    func removeAll() {
        invitations.removeAll()
        relationships.removeAll()
    }
}

