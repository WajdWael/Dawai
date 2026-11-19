//
//  CloudKitSyncTests.swift
//  DawaiTests
//
//  Unit tests for CloudKit event reduction and cross-device merging between Patient and Caregiver.
//

import XCTest
@testable import Dawai

@MainActor
final class CloudKitSyncTests: XCTestCase {

    private let encoder = JSONEncoder()

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    func testCaregiverAddsEditsAndDeletesMedicationSyncsToPatient() throws {
        let patientId = "patient_ck_1"
        let partition = CloudKitSyncManager.patientPartitionKey(for: patientId)
        let t0 = Date(timeIntervalSince1970: 1_795_000_000)

        var med = MedicationItem(
            patientId: patientId,
            name: "بنادول",
            dosage: "500 ملغ",
            timeString: "08:00 ص",
            selectedWeekdays: [1, 3, 5],
            frequency: "مرة يوميًا",
            createdAt: t0
        )

        // 1. Caregiver adds med
        let addEvent = CloudKitSyncEvent(
            partitionKey: partition,
            entityType: .medication,
            entityId: med.id.uuidString,
            updatedAt: t0,
            payloadJSON: try encodeJSON(med)
        )

        let afterAdd = CloudKitSyncReducer.reducePatientEvents([addEvent])
        XCTAssertEqual(afterAdd.medications.count, 1)
        XCTAssertEqual(afterAdd.medications.first?.name, "بنادول")
        XCTAssertEqual(afterAdd.medications.first?.selectedWeekdays, [1, 3, 5])

        // 2. Caregiver edits dosage & time
        med.dosage = "1000 ملغ"
        med.timeString = "09:00 ص"
        let editEvent = CloudKitSyncEvent(
            partitionKey: partition,
            entityType: .medication,
            entityId: med.id.uuidString,
            updatedAt: t0.addingTimeInterval(60),
            payloadJSON: try encodeJSON(med)
        )

        // Apply on a fresh patient MedicationService
        let relStore = InMemoryInvitationStore()
        let relService = RelationshipService(store: relStore)
        let adherenceService = AdherenceService(store: InMemoryDoseRecordStore(), relationshipService: relService)
        let medService = MedicationService(
            store: InMemoryMedicationStore(),
            adherenceService: adherenceService,
            relationshipService: relService,
            enableTimersAndObservers: false,
            schedulesSystemNotifications: false
        )

        let afterEdit = CloudKitSyncReducer.reducePatientEvents([editEvent, addEvent]) // out of order intentionally
        medService.applyRemotePatientState(
            patientId: patientId,
            medications: afterEdit.medications,
            deletedMedicationIds: afterEdit.deletedMedicationIds,
            deletionRequests: afterEdit.deletionRequests,
            deletedRequestIds: afterEdit.deletedRequestIds
        )
        XCTAssertEqual(medService.medicationList(forPatient: patientId).count, 1)
        XCTAssertEqual(medService.medicationList(forPatient: patientId).first?.dosage, "1000 ملغ")
        XCTAssertEqual(medService.medicationList(forPatient: patientId).first?.timeString, "09:00 ص")

        // 3. Caregiver deletes med
        let deleteEvent = CloudKitSyncEvent(
            partitionKey: partition,
            entityType: .medicationDelete,
            entityId: med.id.uuidString,
            updatedAt: t0.addingTimeInterval(120)
        )
        let afterDelete = CloudKitSyncReducer.reducePatientEvents([addEvent, editEvent, deleteEvent])
        medService.applyRemotePatientState(
            patientId: patientId,
            medications: afterDelete.medications,
            deletedMedicationIds: afterDelete.deletedMedicationIds,
            deletionRequests: afterDelete.deletionRequests,
            deletedRequestIds: afterDelete.deletedRequestIds
        )
        XCTAssertTrue(medService.medicationList(forPatient: patientId).isEmpty)
    }

    func testTakenDoseRecordNeverDowngradedByMissedEventAndMergesSameDaySlots() throws {
        let patientId = "patient_ck_2"
        let partition = CloudKitSyncManager.patientPartitionKey(for: patientId)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let sched = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 8, minute: 0)))
        let medId = UUID()

        let takenRecord = DoseRecord(
            patientId: patientId,
            medicationId: medId,
            medicationName: "فيتامين د",
            dosage: "حبة",
            scheduledDate: sched,
            takenDate: sched.addingTimeInterval(300),
            status: .takenOnTime,
            delayMinutes: 5
        )
        let laterMissedRecord = DoseRecord(
            patientId: patientId,
            medicationId: medId,
            medicationName: "فيتامين د",
            dosage: "حبة",
            scheduledDate: sched,
            takenDate: nil,
            status: .missed,
            delayMinutes: 0
        )

        let events = [
            CloudKitSyncEvent(
                partitionKey: partition,
                entityType: .doseRecord,
                entityId: takenRecord.id.uuidString,
                updatedAt: sched.addingTimeInterval(300),
                payloadJSON: try encodeJSON(takenRecord)
            ),
            CloudKitSyncEvent(
                partitionKey: partition,
                entityType: .doseRecord,
                entityId: laterMissedRecord.id.uuidString,
                updatedAt: sched.addingTimeInterval(7200),
                payloadJSON: try encodeJSON(laterMissedRecord)
            )
        ]

        let reduced = CloudKitSyncReducer.reducePatientEvents(events, calendar: cal)
        XCTAssertEqual(reduced.doseRecords.count, 1)
        XCTAssertEqual(reduced.doseRecords.first?.status, .takenOnTime)
    }

    func testRelationshipEstablishAndEndEventsReduceCorrectly() throws {
        let rel = ActiveRelationship(
            invitationId: UUID(),
            patientId: "p_rel_1",
            patientDisplayName: "نورة",
            caregiverId: "c_rel_1",
            caregiverDisplayName: "وجد",
            establishedAt: Date(timeIntervalSince1970: 1_795_000_000),
            isActive: true
        )
        let partition = CloudKitSyncManager.userPartitionKey(for: rel.caregiverId)

        let establishEvent = CloudKitSyncEvent(
            partitionKey: partition,
            entityType: .relationship,
            entityId: rel.id.uuidString,
            updatedAt: rel.establishedAt,
            payloadJSON: try encodeJSON(rel)
        )
        let activeState = CloudKitSyncReducer.reduceUserEvents([establishEvent])
        XCTAssertEqual(activeState.activeRelationships.count, 1)
        XCTAssertEqual(activeState.activeRelationships.first?.patientId, "p_rel_1")

        let endEvent = CloudKitSyncEvent(
            partitionKey: partition,
            entityType: .relationshipEnd,
            entityId: rel.id.uuidString,
            updatedAt: rel.establishedAt.addingTimeInterval(3600)
        )
        let endedState = CloudKitSyncReducer.reduceUserEvents([establishEvent, endEvent])
        XCTAssertTrue(endedState.activeRelationships.isEmpty)
        XCTAssertTrue(endedState.endedRelationshipIds.contains(rel.id))
    }
}

