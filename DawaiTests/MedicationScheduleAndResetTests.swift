//
//  MedicationScheduleAndResetTests.swift
//  DawaiTests
//

import Foundation
import XCTest
@testable import Dawai

@MainActor
final class MedicationScheduleAndResetTests: XCTestCase {
    private struct TestHarness {
        let medStore: InMemoryMedicationStore
        let doseStore: InMemoryDoseRecordStore
        let inviteStore: InMemoryInvitationStore
        let relationshipService: RelationshipService
        let adherenceService: AdherenceService
        let medicationService: MedicationService
        let calendar: Calendar
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
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return TestHarness(
            medStore: medStore,
            doseStore: doseStore,
            inviteStore: inviteStore,
            relationshipService: relationshipService,
            adherenceService: adherenceService,
            medicationService: medicationService,
            calendar: cal
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, calendar: Calendar = .current) -> Date {
        let comps = DateComponents(calendar: calendar, year: year, month: month, day: day, hour: hour, minute: minute, second: 0)
        return comps.date ?? Date()
    }

    // MARK: - 1. Daily Reset
    func testDailyStatusResetsAutomaticallyOnNewDay() async throws {
        defer { AppClock.shared.reset() }
        let h = makeHarness()

        let patient = UserIdentity(id: "patient_reset_1", role: .patient, displayName: "خالد", keyFingerprint: "fp1")
        // Sunday Nov 15, 2026
        let day1Created = date(year: 2026, month: 11, day: 15, hour: 7, minute: 0, calendar: h.calendar)
        let day1Confirm = date(year: 2026, month: 11, day: 15, hour: 8, minute: 5, calendar: h.calendar)
        let day2Morning = date(year: 2026, month: 11, day: 16, hour: 7, minute: 30, calendar: h.calendar)

        AppClock.shared.setSimulatedDate(day1Created)
        let med = MedicationItem(
            patientId: patient.id,
            name: "بنادول",
            dosage: "حبة واحدة",
            timeString: "08:00 ص",
            days: ["كل يوم"],
            frequency: "مرة يوميًا",
            createdAt: day1Created
        )
        try await h.medicationService.addMedication(item: med, currentUser: patient)

        AppClock.shared.setSimulatedDate(day1Confirm)
        let didConfirm = h.medicationService.confirmDoseTaken(id: med.id, patient: patient, at: day1Confirm)
        XCTAssertTrue(didConfirm)
        XCTAssertTrue(h.medicationService.allMedications.first?.isTaken == true)
        XCTAssertEqual(h.medicationService.daySchedule(forPatient: patient.id, at: day1Confirm).remainingDoses, 0)

        // Advance to Monday Nov 16 morning -> status must automatically reset
        AppClock.shared.setSimulatedDate(day2Morning)
        h.medicationService.refreshDerivedState(at: day2Morning)

        let updatedMed = try XCTUnwrap(h.medicationService.allMedications.first)
        XCTAssertFalse(updatedMed.isTaken)
        XCTAssertNil(updatedMed.takenAt)
        XCTAssertTrue(updatedMed.takenSlotsToday.isEmpty)
        XCTAssertEqual(h.medicationService.doseInteractionState(for: updatedMed, at: day2Morning), .upcomingBeforeWindow)
        XCTAssertEqual(h.medicationService.daySchedule(forPatient: patient.id, at: day2Morning).remainingDoses, 1)
        // Yesterday's confirmation stays preserved in adherence history
        XCTAssertTrue(h.adherenceService.hasTakenRecord(for: med.id, on: day1Confirm, slotMinutes: 480))
    }

    func testLegacyIsTakenWithoutTakenAtResetsOnNewDay() async throws {
        defer { AppClock.shared.reset() }
        let h = makeHarness()

        let day1 = date(year: 2026, month: 11, day: 15, hour: 7, minute: 0, calendar: h.calendar)
        let day2 = date(year: 2026, month: 11, day: 16, hour: 8, minute: 0, calendar: h.calendar)
        let legacyMed = MedicationItem(
            patientId: "patient_legacy",
            name: "فيتامين",
            dosage: "حبة واحدة",
            timeString: "08:00 ص",
            isTaken: true,
            takenAt: nil,
            createdAt: day1
        )
        h.medStore.medications = [legacyMed]
        h.medicationService.loadPersistedMedications()

        AppClock.shared.setSimulatedDate(day2)
        h.medicationService.refreshDerivedState(at: day2)

        let refreshed = try XCTUnwrap(h.medicationService.allMedications.first)
        XCTAssertFalse(refreshed.isTaken)
        XCTAssertEqual(h.medicationService.doseInteractionState(for: refreshed, at: day2), .dueOnTime)
    }

    // MARK: - 2. Missed Doses Logged in Adherence & Lower Adherence Report
    func testMissedDosesBackfilledAndLowerAdherencePercentage() async throws {
        defer { AppClock.shared.reset() }
        let h = makeHarness()

        let patient = UserIdentity(id: "patient_report", role: .patient, displayName: "نورة", keyFingerprint: "fp2")
        // Sunday Nov 15 .. Wednesday Nov 18 (all in same Sunday-Saturday week)
        let sundayAnchor = date(year: 2026, month: 11, day: 15, hour: 7, minute: 0, calendar: h.calendar)
        let wednesdayConfirm = date(year: 2026, month: 11, day: 18, hour: 8, minute: 5, calendar: h.calendar)

        AppClock.shared.setSimulatedDate(sundayAnchor)
        let med = MedicationItem(
            patientId: patient.id,
            name: "أسبرين",
            dosage: "حبة واحدة",
            timeString: "08:00 ص",
            days: ["كل يوم"],
            frequency: "مرة يوميًا",
            createdAt: sundayAnchor
        )
        try await h.medicationService.addMedication(item: med, currentUser: patient)

        // Jump to Wednesday 08:05 without ever confirming Sun / Mon / Tue
        AppClock.shared.setSimulatedDate(wednesdayConfirm)
        let confirmedToday = h.medicationService.confirmDoseTaken(id: med.id, patient: patient, at: wednesdayConfirm)
        XCTAssertTrue(confirmedToday)

        let period = try XCTUnwrap(h.adherenceService.availableWeekPeriods(count: 1, referenceDate: wednesdayConfirm).first)
        let report = h.adherenceService.generateWeeklyReport(
            patientId: patient.id,
            patientDisplayName: patient.displayName,
            period: period
        )

        // 4 scheduled days: 3 missed (Sun, Mon, Tue) + 1 taken on time (Wed) -> 25%
        XCTAssertTrue(report.hasSufficientData)
        XCTAssertEqual(report.totalScheduled, 4)
        XCTAssertEqual(report.totalTaken, 1)
        XCTAssertEqual(report.totalMissed, 3)
        XCTAssertEqual(report.adherencePercentage, 25.0, accuracy: 0.01)
    }

    func testSameDayMissedCutoffRecordsMissedDose() async throws {
        defer { AppClock.shared.reset() }
        let h = makeHarness()

        let patient = UserIdentity(id: "patient_sameday_miss", role: .patient, displayName: "فهد", keyFingerprint: "fp3")
        let morningCreate = date(year: 2026, month: 11, day: 18, hour: 7, minute: 30, calendar: h.calendar)
        let afterCutoff = date(year: 2026, month: 11, day: 18, hour: 10, minute: 5, calendar: h.calendar) // +125m

        AppClock.shared.setSimulatedDate(morningCreate)
        let med = MedicationItem(
            patientId: patient.id,
            name: "مضاد",
            dosage: "كبسولة",
            timeString: "08:00 ص",
            days: ["كل يوم"],
            frequency: "مرة يوميًا",
            createdAt: morningCreate
        )
        try await h.medicationService.addMedication(item: med, currentUser: patient)

        AppClock.shared.setSimulatedDate(afterCutoff)
        h.medicationService.refreshDerivedState(at: afterCutoff)

        let period = try XCTUnwrap(h.adherenceService.availableWeekPeriods(count: 1, referenceDate: afterCutoff).first)
        let report = h.adherenceService.generateWeeklyReport(
            patientId: patient.id,
            patientDisplayName: patient.displayName,
            period: period
        )

        XCTAssertEqual(report.totalScheduled, 1)
        XCTAssertEqual(report.totalTaken, 0)
        XCTAssertEqual(report.totalMissed, 1)
        XCTAssertEqual(report.adherencePercentage, 0.0, accuracy: 0.01)
    }

    // MARK: - 3. Weekday-Specific Scheduling & Midnight Shift
    func testWeekdaySpecificRemindersDoNotRepeatDaily() {
        let h = makeHarness()

        let weekdayMed = MedicationItem(
            patientId: "patient_weekdays",
            name: "فيتامين د",
            dosage: "حبة واحدة",
            timeString: "11:45 م",
            days: ["كل الاحد", "كل الثلاثاء"],
            frequency: "مرة يوميًا"
        )

        XCTAssertEqual(h.medicationService.scheduledWeekdays(for: weekdayMed), [1, 3])

        let reminders = h.medicationService.plannedReminders(for: weekdayMed)
        XCTAssertEqual(reminders.count, 2)
        XCTAssertEqual(Set(reminders.compactMap(\.weekday)), [1, 3])
        XCTAssertTrue(reminders.allSatisfy { $0.repeats && $0.hour == 23 && $0.minute == 45 })

        // 11:45 PM + 30m crosses midnight -> 00:15 AM on Monday (2) & Wednesday (4)
        let checkDate = date(year: 2026, month: 11, day: 16, hour: 10, minute: 0, calendar: h.calendar) // Monday
        let missedAlerts = h.medicationService.plannedMissedDoseAlerts(for: weekdayMed, at: checkDate)
        XCTAssertEqual(missedAlerts.count, 2)
        XCTAssertEqual(Set(missedAlerts.compactMap(\.weekday)), [2, 4])
        XCTAssertTrue(missedAlerts.allSatisfy { $0.hour == 0 && $0.minute == 15 && $0.repeats })
    }

    // MARK: - 4. Multi-Dose Frequency (Independent Slots, Alerts & Reporting)
    func testMultiDoseFrequencyGeneratesIndependentSlotsAndTracking() async throws {
        defer { AppClock.shared.reset() }
        let h = makeHarness()

        let patient = UserIdentity(id: "patient_multi", role: .patient, displayName: "سارة", keyFingerprint: "fp4")
        let createdAt = date(year: 2026, month: 11, day: 18, hour: 7, minute: 0, calendar: h.calendar)
        let morningWindow = date(year: 2026, month: 11, day: 18, hour: 8, minute: 5, calendar: h.calendar)
        let nightMissedCheck = date(year: 2026, month: 11, day: 18, hour: 22, minute: 5, calendar: h.calendar) // +125m after 20:00

        // Verify parsing across common Arabic frequency modes
        let twiceDaily = MedicationItem(patientId: patient.id, name: "أ", dosage: "1 حبة", timeString: "08:00 ص", frequency: "مرتان يومياً", createdAt: createdAt)
        let every8h = MedicationItem(patientId: patient.id, name: "ب", dosage: "1 حبة", timeString: "08:00 ص", frequency: "كل 8 ساعات", createdAt: createdAt)
        let fourTimes = MedicationItem(patientId: patient.id, name: "ج", dosage: "1 حبة", timeString: "08:00 ص", frequency: "4 مرات يومياً", createdAt: createdAt)
        XCTAssertEqual(h.medicationService.dailyDoseTimesMinutes(for: twiceDaily), [480, 1200])
        XCTAssertEqual(h.medicationService.dailyDoseTimesMinutes(for: every8h), [0, 480, 960])
        XCTAssertEqual(h.medicationService.dailyDoseTimesMinutes(for: fourTimes), [120, 480, 840, 1200])

        AppClock.shared.setSimulatedDate(createdAt)
        let every12hMed = MedicationItem(
            patientId: patient.id,
            name: "مضاد حيوي",
            dosage: "حبة",
            timeString: "08:00 ص",
            days: ["كل يوم"],
            frequency: "كل 12 ساعة",
            createdAt: createdAt
        )
        try await h.medicationService.addMedication(item: every12hMed, currentUser: patient)

        XCTAssertEqual(h.medicationService.dailyDoseTimesMinutes(for: every12hMed), [480, 1200])
        XCTAssertEqual(h.medicationService.plannedReminders(for: every12hMed).count, 2)

        let initialSchedule = h.medicationService.daySchedule(forPatient: patient.id, at: morningWindow)
        XCTAssertEqual(initialSchedule.todayDoses.count, 2)
        XCTAssertEqual(initialSchedule.remainingDoses, 2)

        // Confirm only the 08:00 ص dose
        AppClock.shared.setSimulatedDate(morningWindow)
        let confirmedMorning = h.medicationService.confirmDoseTaken(id: every12hMed.id, slotMinutes: 480, patient: patient, at: morningWindow)
        XCTAssertTrue(confirmedMorning)

        let storedAfterMorning = try XCTUnwrap(h.medicationService.allMedications.first)
        XCTAssertFalse(storedAfterMorning.isTaken) // evening dose still untaken!
        XCTAssertEqual(storedAfterMorning.takenSlotsToday.keys.sorted(), [480])

        let scheduleAfterMorning = h.medicationService.daySchedule(forPatient: patient.id, at: morningWindow)
        XCTAssertEqual(scheduleAfterMorning.remainingDoses, 1)
        XCTAssertEqual(scheduleAfterMorning.activeDoses.map(\.slotMinutes), [1200])

        // Miss the 08:00 م dose (>120m late)
        AppClock.shared.setSimulatedDate(nightMissedCheck)
        h.medicationService.refreshDerivedState(at: nightMissedCheck)

        let period = try XCTUnwrap(h.adherenceService.availableWeekPeriods(count: 1, referenceDate: nightMissedCheck).first)
        let report = h.adherenceService.generateWeeklyReport(
            patientId: patient.id,
            patientDisplayName: patient.displayName,
            period: period
        )
        XCTAssertEqual(report.totalScheduled, 2)
        XCTAssertEqual(report.totalTaken, 1)
        XCTAssertEqual(report.totalMissed, 1)
        XCTAssertEqual(report.adherencePercentage, 50.0, accuracy: 0.01)
    }

    // MARK: - 5. Missed-Dose Alert Resilience After Confirming Today
    func testMissedDoseAlertPersistsAcrossFutureDaysAfterTodayConfirmation() async throws {
        defer { AppClock.shared.reset() }
        let h = makeHarness()

        let patient = UserIdentity(id: "patient_alerts", role: .patient, displayName: "ريم", keyFingerprint: "fp5")

        // Case A: Daily medication confirmed at 08:05 (before 08:30 alert)
        let sundayMorning = date(year: 2026, month: 11, day: 15, hour: 8, minute: 5, calendar: h.calendar)
        AppClock.shared.setSimulatedDate(sundayMorning)
        let dailyMed = MedicationItem(
            patientId: patient.id,
            name: "دواء يومي",
            dosage: "حبة",
            timeString: "08:00 ص",
            days: ["كل يوم"],
            frequency: "مرة يوميًا",
            createdAt: date(year: 2026, month: 11, day: 15, hour: 7, minute: 0, calendar: h.calendar)
        )
        try await h.medicationService.addMedication(item: dailyMed, currentUser: patient)
        _ = h.medicationService.confirmDoseTaken(id: dailyMed.id, slotMinutes: 480, patient: patient, at: sundayMorning)

        let confirmedDailyMed = try XCTUnwrap(h.medicationService.allMedications.first(where: { $0.id == dailyMed.id }))
        let dailyAlerts = h.medicationService.plannedMissedDoseAlerts(for: confirmedDailyMed, at: sundayMorning)
        XCTAssertEqual(dailyAlerts.count, 3)
        XCTAssertEqual(dailyAlerts.compactMap(\.day), [16, 17, 18])
        XCTAssertTrue(dailyAlerts.allSatisfy { !$0.repeats && $0.hour == 8 && $0.minute == 30 })

        // Case B: Specific weekdays (Sun/Tue/Thu) confirmed on Sunday 08:05
        let triWeeklyMed = MedicationItem(
            patientId: patient.id,
            name: "دواء ثلاث أيام",
            dosage: "حبة",
            timeString: "08:00 ص",
            days: ["كل الاحد", "كل الثلاثاء", "كل الخميس"],
            frequency: "مرة يوميًا",
            createdAt: date(year: 2026, month: 11, day: 15, hour: 7, minute: 0, calendar: h.calendar)
        )
        try await h.medicationService.addMedication(item: triWeeklyMed, currentUser: patient)
        _ = h.medicationService.confirmDoseTaken(id: triWeeklyMed.id, slotMinutes: 480, patient: patient, at: sundayMorning)

        let confirmedTriMed = try XCTUnwrap(h.medicationService.allMedications.first(where: { $0.id == triWeeklyMed.id }))
        let triAlerts = h.medicationService.plannedMissedDoseAlerts(for: confirmedTriMed, at: sundayMorning)
        let repeatingWeekdays = Set(triAlerts.filter(\.repeats).compactMap(\.weekday))
        let nextWeekSundayOneShots = triAlerts.filter { !$0.repeats }
        XCTAssertEqual(repeatingWeekdays, [3, 5]) // Tuesday & Thursday stay repeating
        XCTAssertEqual(nextWeekSundayOneShots.count, 1)
        XCTAssertEqual(nextWeekSundayOneShots.first?.day, 22) // Next Sunday Nov 22
    }

    func testIntervalAndMonthlyRemindersDoNotRepeatDaily() {
        let h = makeHarness()
        let sundayMorning = date(year: 2026, month: 11, day: 15, hour: 7, minute: 0, calendar: h.calendar)

        // Every 2 days starting Nov 15 -> concrete non-repeating dates Nov 15, 17, 19, 21, 23, 25, 27
        let everyTwoDaysMed = MedicationItem(
            patientId: "p_interval",
            name: "دواء كل يومين",
            dosage: "حبة",
            timeString: "09:00 ص",
            days: ["كل يوم"],
            frequency: "كل يومين",
            createdAt: sundayMorning
        )
        let twoDayReminders = h.medicationService.plannedReminders(for: everyTwoDaysMed, at: sundayMorning)
        XCTAssertEqual(twoDayReminders.count, 7)
        XCTAssertTrue(twoDayReminders.allSatisfy { !$0.repeats && $0.hour == 9 && $0.minute == 0 })
        XCTAssertEqual(twoDayReminders.compactMap(\.day), [15, 17, 19, 21, 23, 25, 27])

        let twoDayAlerts = h.medicationService.plannedMissedDoseAlerts(for: everyTwoDaysMed, at: sundayMorning)
        XCTAssertEqual(twoDayAlerts.count, 7)
        XCTAssertTrue(twoDayAlerts.allSatisfy { !$0.repeats && $0.hour == 9 && $0.minute == 30 })
        XCTAssertEqual(twoDayAlerts.compactMap(\.day), [15, 17, 19, 21, 23, 25, 27])

        // Monthly on the 15th -> repeating trigger pinned to day=15 (not daily)
        let monthlyMed = MedicationItem(
            patientId: "p_interval",
            name: "دواء شهري",
            dosage: "إبرة",
            timeString: "10:00 ص",
            days: ["كل يوم"],
            frequency: "شهرياً",
            createdAt: sundayMorning
        )
        let monthlyReminders = h.medicationService.plannedReminders(for: monthlyMed, at: sundayMorning)
        XCTAssertEqual(monthlyReminders.count, 1)
        XCTAssertEqual(monthlyReminders.first?.day, 15)
        XCTAssertEqual(monthlyReminders.first?.repeats, true)
        XCTAssertNil(monthlyReminders.first?.weekday)

        let monthlyAlerts = h.medicationService.plannedMissedDoseAlerts(for: monthlyMed, at: sundayMorning)
        XCTAssertEqual(monthlyAlerts.count, 1)
        XCTAssertEqual(monthlyAlerts.first?.day, 15)
        XCTAssertEqual(monthlyAlerts.first?.hour, 10)
        XCTAssertEqual(monthlyAlerts.first?.minute, 30)
        XCTAssertEqual(monthlyAlerts.first?.repeats, true)
    }

    func testStructuredSelectedWeekdaysModelAndCodableRoundTrip() throws {
        let h = makeHarness()
        let med = MedicationItem(
            patientId: "p_struct",
            name: "دواء أيام مهيكلة",
            dosage: "حبة",
            timeString: "08:00 ص",
            selectedWeekdays: [MedicationWeekday.sunday.rawValue, MedicationWeekday.wednesday.rawValue],
            frequency: "مرة يوميًا"
        )

        XCTAssertEqual(med.selectedWeekdays, [1, 4])
        XCTAssertEqual(med.days, ["كل الاحد", "كل الاربعاء"])
        XCTAssertEqual(h.medicationService.scheduledWeekdays(for: med), [1, 4])

        let data = try JSONEncoder().encode(med)
        let decoded = try JSONDecoder().decode(MedicationItem.self, from: data)
        XCTAssertEqual(decoded.selectedWeekdays, [1, 4])
        XCTAssertEqual(decoded.days, ["كل الاحد", "كل الاربعاء"])

        let reminders = h.medicationService.plannedReminders(for: decoded)
        XCTAssertEqual(reminders.count, 2)
        XCTAssertEqual(Set(reminders.compactMap(\.weekday)), [1, 4])
        XCTAssertTrue(reminders.allSatisfy { $0.repeats && $0.hour == 8 && $0.minute == 0 })
    }
}

