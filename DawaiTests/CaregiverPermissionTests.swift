//
//  CaregiverPermissionTests.swift
//  DawaiTests
//

import Foundation
import XCTest
@testable import Dawai

@MainActor
final class CaregiverPermissionTests: XCTestCase {
    private struct TestHarness {
        let relationshipService: RelationshipService
        let adherenceService: AdherenceService
        let medicationService: MedicationService
    }

    private func makeHarness() -> TestHarness {
        let medStore = InMemoryMedicationStore()
        let doseStore = InMemoryDoseRecordStore()
        let inviteStore = InMemoryInvitationStore()
        let relationshipService = RelationshipService(store: inviteStore)
        let adherenceService = AdherenceService(store: doseStore, relationshipService: relationshipService)
        let medicationService = MedicationService(
            store: medStore,
            adherenceService: adherenceService,
            relationshipService: relationshipService,
            enableTimersAndObservers: false,
            schedulesSystemNotifications: false
        )
        return TestHarness(
            relationshipService: relationshipService,
            adherenceService: adherenceService,
            medicationService: medicationService
        )
    }

    private func link(
        patient: UserIdentity,
        caregiver: UserIdentity,
        via relationshipService: RelationshipService
    ) throws -> ActiveRelationship {
        let invite = relationshipService.createInvitation(initiator: patient)
        _ = try relationshipService.acceptInvitation(token: invite.token, recipient: caregiver)
        return try XCTUnwrap(relationshipService.activeCaregiver(forPatient: patient.id))
    }

    func testLinkedCaregiverAuthorizedWithPatientId() async throws {
        let h = makeHarness()
        let patient = UserIdentity(id: "patient_auth_1", role: .patient, displayName: "أبو خالد", keyFingerprint: "fp_p1")
        let caregiver = UserIdentity(id: "caregiver_auth_1", role: .caregiver, displayName: "أحمد", keyFingerprint: "fp_c1")

        let relationship = try link(patient: patient, caregiver: caregiver, via: h.relationshipService)
        XCTAssertEqual(relationship.patientId, patient.id)
        XCTAssertNotEqual(relationship.id.uuidString, patient.id)

        // 1. Add medication using patientId -> succeeds
        let med = MedicationItem(
            patientId: patient.id,
            name: "منظم السكر",
            dosage: "حبة واحدة",
            timeString: "09:00 ص"
        )
        try await h.medicationService.addMedication(
            item: med,
            currentUser: caregiver,
            targetPatientId: patient.id
        )
        XCTAssertEqual(h.medicationService.medicationList(forPatient: patient.id).count, 1)

        // 2. Edit medication using patientId -> succeeds
        var editedMed = med
        editedMed.dosage = "حبتان"
        try await h.medicationService.updateMedication(
            item: editedMed,
            currentUser: caregiver,
            targetPatientId: patient.id
        )
        XCTAssertEqual(h.medicationService.medicationList(forPatient: patient.id).first?.dosage, "حبتان")

        // 3. Report access verification using patientId -> authorized
        let access = h.adherenceService.verifyAccess(actor: caregiver, targetPatientId: patient.id)
        XCTAssertTrue(access.isAuthorized)
        XCTAssertNil(access.errorReason)
    }

    func testCaregiverRejectedWhenPassingRelationshipIdInsteadOfPatientId() async throws {
        let h = makeHarness()
        let patient = UserIdentity(id: "patient_auth_2", role: .patient, displayName: "أم سارة", keyFingerprint: "fp_p2")
        let caregiver = UserIdentity(id: "caregiver_auth_2", role: .caregiver, displayName: "سلمان", keyFingerprint: "fp_c2")

        let relationship = try link(patient: patient, caregiver: caregiver, via: h.relationshipService)
        let wrongId = relationship.id.uuidString

        let med = MedicationItem(
            patientId: wrongId,
            name: "ضغط الدم",
            dosage: "حبة واحدة",
            timeString: "10:00 ص"
        )

        do {
            try await h.medicationService.addMedication(
                item: med,
                currentUser: caregiver,
                targetPatientId: wrongId
            )
            XCTFail("Expected unauthorizedCaregiver error when relationship id is passed instead of patient id")
        } catch let error as MedicationError {
            XCTAssertEqual(error, .unauthorizedCaregiver)
        }

        let access = h.adherenceService.verifyAccess(actor: caregiver, targetPatientId: wrongId)
        XCTAssertFalse(access.isAuthorized)
        XCTAssertNotNil(access.errorReason)
    }

    func testUnlinkedOrDisconnectedCaregiverRejected() async throws {
        let h = makeHarness()
        let patient = UserIdentity(id: "patient_auth_3", role: .patient, displayName: "فيصل", keyFingerprint: "fp_p3")
        let caregiver = UserIdentity(id: "caregiver_auth_3", role: .caregiver, displayName: "عمر", keyFingerprint: "fp_c3")
        let strangerCaregiver = UserIdentity(id: "caregiver_stranger", role: .caregiver, displayName: "غريب", keyFingerprint: "fp_c4")

        let relationship = try link(patient: patient, caregiver: caregiver, via: h.relationshipService)

        // Stranger caregiver is rejected for add & report
        let strangerMed = MedicationItem(patientId: patient.id, name: "دواء", dosage: "حبة", timeString: "08:00 ص")
        do {
            try await h.medicationService.addMedication(item: strangerMed, currentUser: strangerCaregiver, targetPatientId: patient.id)
            XCTFail("Expected stranger caregiver to be rejected")
        } catch let error as MedicationError {
            XCTAssertEqual(error, .unauthorizedCaregiver)
        }
        XCTAssertFalse(h.adherenceService.verifyAccess(actor: strangerCaregiver, targetPatientId: patient.id).isAuthorized)

        // Linked caregiver succeeds before disconnect, then is rejected after disconnect
        try await h.medicationService.addMedication(item: strangerMed, currentUser: caregiver, targetPatientId: patient.id)
        h.relationshipService.disconnect(relationshipId: relationship.id)

        XCTAssertFalse(h.adherenceService.verifyAccess(actor: caregiver, targetPatientId: patient.id).isAuthorized)
        var edited = strangerMed
        edited.dosage = "نصف حبة"
        do {
            try await h.medicationService.updateMedication(item: edited, currentUser: caregiver, targetPatientId: patient.id)
            XCTFail("Expected disconnected caregiver edit to be rejected")
        } catch let error as MedicationError {
            XCTAssertEqual(error, .unauthorizedCaregiver)
        }
    }
}

