//
//  DoseLiveActivityManager.swift
//  Dawai
//
//  Manages the Dynamic Island & Lock Screen Live Activity for the patient's active or next upcoming dose.
//

import Foundation
import ActivityKit

@MainActor
public final class DoseLiveActivityManager {
    public static let shared = DoseLiveActivityManager()

    public static let liveActivityEnabledKey = "dawai_live_activity_enabled"

    /// Maximum lookahead window (24 hours) for displaying an upcoming dose countdown in Dynamic Island.
    private let upcomingLookaheadSeconds: TimeInterval = 24 * 60 * 60

    private var lastAppliedState: DawaiDoseActivityAttributes.ContentState?

    public var isUserEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: Self.liveActivityEnabledKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.liveActivityEnabledKey)
        }
    }

    public var areSystemActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private init() {}

    /// Synchronizes the Dynamic Island & Lock Screen Live Activity with the patient's current schedule.
    public func sync(using medicationService: MedicationService, at date: Date? = nil) {
        guard !isRunningTests else { return }

        let notificationsEnabled = UserDefaults.standard.object(forKey: "dawai_notifications_enabled") as? Bool ?? true
        guard isUserEnabled, notificationsEnabled else {
            endAllActivities()
            return
        }

        guard let identity = KeychainService.shared.loadUserIdentity(),
              identity.role == .patient else {
            endAllActivities()
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let now = date ?? AppClock.shared.now
        guard let targetState = computeTargetContentState(using: medicationService, at: now) else {
            endAllActivities()
            return
        }

        // Skip redundant updates when nothing changed
        if lastAppliedState == targetState,
           !Activity<DawaiDoseActivityAttributes>.activities.isEmpty {
            return
        }

        lastAppliedState = targetState

        Task {
            await upsertActivity(patientName: identity.displayName, state: targetState)
        }
    }

    public func endAllActivities() {
        lastAppliedState = nil
        guard !isRunningTests else { return }
        let activities = Activity<DawaiDoseActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Priority Selection

    /// Picks the highest-priority dose to feature in Dynamic Island:
    /// 1) Overdue late dose, 2) Due on-time dose, 3) Next upcoming dose within 8 hours.
    public func computeTargetContentState(
        using medicationService: MedicationService,
        at now: Date
    ) -> DawaiDoseActivityAttributes.ContentState? {
        let activeDoses = medicationService.activeDoses
        let remainingCount = medicationService.remainingDoses

        // 1 & 2: Already active (.overdueLate comes before .dueOnTime in activeDoses)
        if let active = activeDoses.first {
            let state = medicationService.doseInteractionState(
                for: active.medication,
                slotMinutes: active.slotMinutes,
                at: now
            )
            let phase: String = (state == .overdueLate) ? "late" : "due"
            let schedDay = active.isCarryoverFromYesterday
                ? (Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now)
                : now
            let schedDate = medicationService.scheduledDateTime(
                for: active.medication,
                on: schedDay,
                slotMinutes: active.slotMinutes
            )
            return DawaiDoseActivityAttributes.ContentState(
                medicationId: active.medication.id.uuidString,
                medicationName: active.medication.name,
                dosage: active.medication.dosage,
                timeString: active.timeString,
                slotMinutes: active.slotMinutes,
                scheduledDate: schedDate,
                phase: phase,
                remainingDosesCount: max(remainingCount, 1)
            )
        }

        // 3: Next upcoming dose today within the 8-hour lookahead window
        var upcomingCandidates: [(med: MedicationItem, slot: Int, schedDate: Date, timeString: String)] = []
        for med in medicationService.todayMedications {
            for slot in medicationService.dailyDoseTimesMinutes(for: med) {
                let state = medicationService.doseInteractionState(for: med, slotMinutes: slot, at: now)
                guard state == .upcomingBeforeWindow else { continue }
                let schedDate = medicationService.scheduledDateTime(for: med, on: now, slotMinutes: slot)
                let delta = schedDate.timeIntervalSince(now)
                guard delta > 0 && delta <= upcomingLookaheadSeconds else { continue }
                upcomingCandidates.append((
                    med: med,
                    slot: slot,
                    schedDate: schedDate,
                    timeString: medicationService.formattedTimeString(forSlotMinutes: slot)
                ))
            }
        }
        upcomingCandidates.sort { $0.schedDate < $1.schedDate }

        if let next = upcomingCandidates.first {
            return DawaiDoseActivityAttributes.ContentState(
                medicationId: next.med.id.uuidString,
                medicationName: next.med.name,
                dosage: next.med.dosage,
                timeString: next.timeString,
                slotMinutes: next.slot,
                scheduledDate: next.schedDate,
                phase: "upcoming",
                remainingDosesCount: max(remainingCount, 1)
            )
        }

        return nil
    }

    // MARK: - ActivityKit Upsert

    private func upsertActivity(
        patientName: String,
        state: DawaiDoseActivityAttributes.ContentState
    ) async {
        let staleDate = state.scheduledDate.addingTimeInterval(TimeInterval(DoseWindowConfig.missedCutoffMinutes * 60))
        let content = ActivityContent(state: state, staleDate: staleDate)
        let existing = Activity<DawaiDoseActivityAttributes>.activities

        if let primary = existing.first {
            // End any stray duplicates
            if existing.count > 1 {
                for extra in existing.dropFirst() {
                    await extra.end(nil, dismissalPolicy: .immediate)
                }
            }
            await primary.update(content)
        } else {
            let attributes = DawaiDoseActivityAttributes(patientName: patientName)
            _ = try? Activity<DawaiDoseActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        }
    }
}
