//
//  CaregiverPatientDetailView.swift
//  Dawai
//
//  Caregiver view of a specific beneficiary ("P page - caregiver")
//  Decomposed into lightweight @ViewBuilder subviews to ensure fast type-checking.
//

import SwiftUI

public struct CaregiverPatientDetailView: View {
    let beneficiary: BeneficiarySummary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var medicationService = MedicationService.shared
    @ObservedObject private var relationshipService = RelationshipService.shared
    @ObservedObject private var themeService = ThemeService.shared

    @State private var showingCallAlert = false
    @State private var enteredPhoneNumber: String = ""
    @State private var showingUnlinkAlert = false
    @State private var showingReportSheet = false
    @State private var showingAddMedicationSheet = false
    @State private var editingMedication: MedicationItem? = nil
    @State private var previewingMedication: MedicationItem? = nil

    // UC-11 Direct Deletion by Caregiver
    @State private var medicationToDelete: MedicationItem? = nil
    @State private var showingCaregiverDeleteAlert = false
    @State private var swipedItemId: String? = nil

    public init(beneficiary: BeneficiarySummary) {
        self.beneficiary = beneficiary
    }

    // MARK: - Patient Scope
    /// The real patient identity id. Empty when the row has no patient behind it, which matches no data.
    private var beneficiaryPatientId: String {
        beneficiary.patientId ?? ""
    }

    /// Today's schedule built only from this patient's medications.
    private var currentSchedule: MedicationService.PatientDaySchedule {
        medicationService.daySchedule(forPatient: beneficiaryPatientId, at: medicationService.lastEvaluatedAt)
    }

    /// All medications owned by this patient.
    private var currentPatientMedications: [MedicationItem] {
        medicationService.medicationList(forPatient: beneficiaryPatientId)
    }

    /// The active link between the signed-in caregiver and this patient. `nil` for demo rows or ended links.
    private var activeRelationship: ActiveRelationship? {
        guard let caregiverId = appState.currentIdentity?.id, let patientId = beneficiary.patientId else { return nil }
        return relationshipService.activeRelationships.first {
            $0.caregiverId == caregiverId && $0.patientId == patientId && $0.isActive
        }
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    navigationBarView

                    if beneficiary.hasDelayAlert {
                        delayAlertBanner
                    }

                    // UC-11 Collaborative Approval: Pending Deletion Requests
                    pendingDeletionRequestsSection

                    medicationsSection
                    upcomingDosesSection
                    asNeededMedicationsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 80)
            }
            .refreshable {
                await CloudKitSyncManager.shared.syncNow(silent: false)
            }

            // Pinned at the very bottom of the screen (not inside scroll content)
            if activeRelationship != nil || DemoModeService.shared.isActive {
                unlinkButton
            }

            // Notification Toast (Add / Edit / Delete Feedback)
            if let toastMessage = medicationService.toastMessage ?? RelationshipService.shared.notificationToastMessage {
                NotificationToastView(message: toastMessage) {
                    medicationService.dismissToast()
                    RelationshipService.shared.dismissToast()
                }
            }
        }
        .background(Color.dawaiBackground.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale.dawaiArabic)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            themeService.applyThemeToApp()
            medicationService.refreshDerivedState()
            Task {
                await CloudKitSyncManager.shared.syncNow(silent: true)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                medicationService.refreshDerivedState()
                Task {
                    await CloudKitSyncManager.shared.syncNow(silent: true)
                }
            }
        }
        .preferredColorScheme(themeService.colorScheme)
        .alert("الاتصال بـ \(beneficiary.name)", isPresented: $showingCallAlert) {
            TextField("رقم الجوال (مثال: 05XXXXXXXX)", text: $enteredPhoneNumber)
                .keyboardType(.phonePad)

            Button("اتصال") {
                let clean = enteredPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
                if !clean.isEmpty {
                    UserDefaults.standard.set(clean, forKey: "saved_phone_\(beneficiary.name)")
                    if let url = URL(string: "tel://\(clean)"), UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    }
                }
            }

            Button("فتح تطبيق الهاتف") {
                if let url = URL(string: "tel://") {
                    UIApplication.shared.open(url)
                }
            }

            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("أدخل رقم جوال \(beneficiary.name) للاتصال المباشر به، أو افتح تطبيق الهاتف.")
        }
        .sheet(isPresented: $showingReportSheet) {
            let caregiverUser = appState.currentIdentity ?? UserIdentity(role: .caregiver, displayName: "مقدم الرعاية", keyFingerprint: "cg_default")
            AdherenceReportView(
                currentUser: caregiverUser,
                targetPatientId: beneficiary.patientId,
                targetPatientName: beneficiary.name
            )
            .preferredColorScheme(themeService.colorScheme)
        }
        .sheet(isPresented: $showingAddMedicationSheet) {
            let caregiverUser = appState.currentIdentity ?? UserIdentity(role: .caregiver, displayName: "مقدم الرعاية", keyFingerprint: "cg_default")
            MedicationFormView(mode: .add, currentUser: caregiverUser, targetPatient: beneficiary) {
                showingAddMedicationSheet = false
            }
            .preferredColorScheme(themeService.colorScheme)
        }
        .sheet(item: $previewingMedication) { med in
            medicationPreviewSheet(for: med)
                .preferredColorScheme(themeService.colorScheme)
        }
        .sheet(item: $editingMedication) { med in
            let caregiverUser = appState.currentIdentity ?? UserIdentity(role: .caregiver, displayName: "مقدم الرعاية", keyFingerprint: "cg_default")
            MedicationFormView(mode: .edit(med), currentUser: caregiverUser, targetPatient: beneficiary) {
                editingMedication = nil
            }
            .preferredColorScheme(themeService.colorScheme)
        }
        .alert("حذف الدواء للمستفيد", isPresented: $showingCaregiverDeleteAlert) {
            Button("حذف نهائياً", role: .destructive) {
                if let med = medicationToDelete {
                    medicationService.deleteMedicationByCaregiver(id: med.id, patientName: beneficiary.name)
                }
                medicationToDelete = nil
            }
            Button("إلغاء", role: .cancel) {
                medicationToDelete = nil
            }
        } message: {
            Text("هل أنت متأكد من رغبتك في حذف دواء \"\(medicationToDelete?.name ?? "")\"؟ سيتم حذفه نهائياً من جدول \(beneficiary.name) وإلغاء جميع التذكيرات.")
        }
        .confirmationDialog(
            "إنهاء الارتباط مع \(beneficiary.name)؟",
            isPresented: $showingUnlinkAlert,
            titleVisibility: .visible
        ) {
            Button("إنهاء الارتباط", role: .destructive) {
                if let rel = activeRelationship {
                    relationshipService.disconnect(relationshipId: rel.id)
                    dismiss()
                }
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("لن تتمكن من متابعة أدوية وجرعات \(beneficiary.name)، ولن تصلك تنبيهات عند فوات جرعة.")
        }
    }

    // MARK: - End Link Button (Pinned at Screen Bottom)
    @ViewBuilder
    private var unlinkButton: some View {
        Button(role: .destructive) {
            showingUnlinkAlert = true
        } label: {
            Text("إنهاء الارتباط")
                .dawaiFont(size: 14, weight: .medium)
                .foregroundStyle(Color.red)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel("إنهاء الارتباط مع \(beneficiary.name)")
    }

    // MARK: - 1. Navigation Bar (Strict RTL: Back button on Leading/Right, Actions on Trailing/Left)
    @ViewBuilder
    private var navigationBarView: some View {
        HStack {
            // Leading side (RIGHT in RTL): Back button with chevron pointing right
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.right")
                    .dawaiFont(size: 18, weight: .bold)
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().stroke(Color.dawaiGlassBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("رجوع")

            Spacer()

            // Center: Beneficiary Name
            Text(beneficiary.name)
                .dawaiFont(size: 26, weight: .bold, design: .rounded)
                .foregroundStyle(.primary)

            Spacer()

            // Trailing side (LEFT in RTL): Call & Report Sheet buttons
            HStack(spacing: 8) {
                Button {
                    let saved = UserDefaults.standard.string(forKey: "saved_phone_\(beneficiary.name)")
                    enteredPhoneNumber = saved ?? (beneficiary.phoneNumber == "0501234567" ? "" : (beneficiary.phoneNumber ?? ""))
                    showingCallAlert = true
                } label: {
                    Image(systemName: "phone.fill")
                        .dawaiFont(size: 16, weight: .bold)
                        .foregroundStyle(Color.dawaiPrimary)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(
                            Circle().stroke(Color.dawaiGlassBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("اتصال بـ \(beneficiary.name)")

                Button {
                    showingReportSheet = true
                } label: {
                    Image(systemName: "doc.text")
                        .dawaiFont(size: 18, weight: .semibold)
                        .foregroundStyle(Color.dawaiPrimary)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(
                            Circle().stroke(Color.dawaiGlassBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("تقرير الجرعات")
            }
        }
        .padding(.top, 8)
    }

    // MARK: - 2. Delay Alert Banner (Refined Warm Amber Alert Card)
    @ViewBuilder
    private var delayAlertBanner: some View {
        let schedule = currentSchedule
        let medName = beneficiary.delayedMedicationName ?? schedule.missedMedications.first?.name ?? schedule.activeMedication?.name ?? "الدواء"
        let dosage = beneficiary.delayedDosage ?? schedule.missedMedications.first?.dosage ?? "جرعة مجدولة"
        let scheduledTime = beneficiary.scheduledTime ?? schedule.missedDoses.first?.timeString ?? schedule.missedMedications.first?.timeString ?? "11:30 م"
        let noticeTitle = beneficiary.delayNotice ?? "30 د تأخير، \(medName)"

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .dawaiFont(size: 20)
                    .foregroundStyle(Color.dawaiWarning)

                Text(noticeTitle)
                    .dawaiFont(size: 18, weight: .bold)
                    .foregroundStyle(.primary)

                Spacer()
            }

            HStack {
                Text("\(dosage)، مجدولة: \(scheduledTime)")
                    .dawaiFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color.dawaiWarning)

                Spacer()
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.dawaiWarning.opacity(0.3), lineWidth: 1.0)
        )
    }

    // MARK: - 2.5 Pending Deletion Requests Section (UC-11 Collaborative Approval)
    @ViewBuilder
    private var pendingDeletionRequestsSection: some View {
        // Match by the real patient id only (never by display name or a fixed id).
        let requests = medicationService.pendingDeletionRequests.filter { req in
            guard let patientId = beneficiary.patientId else { return false }
            return req.patientId == patientId
        }
        if !requests.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .dawaiFont(size: 18)
                        .foregroundStyle(Color.dawaiWarning)
                    Text("طلبات حذف الأدوية من المستفيد")
                        .dawaiFont(size: 18, weight: .bold)
                        .foregroundStyle(.primary)
                }

                ForEach(requests) { req in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(req.medicationName)
                                    .dawaiFont(size: 17, weight: .bold)
                                    .foregroundStyle(.primary)
                                Text("\(req.dosage) • \(req.timeString)")
                                    .dawaiFont(size: 13, weight: .medium)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "hourglass")
                                    .dawaiFont(size: 10, weight: .bold)
                                Text("طلب حذف")
                                    .dawaiFont(size: 11, weight: .bold)
                            }
                            .foregroundStyle(Color.dawaiWarning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.dawaiWarningBackground, in: Capsule())
                        }

                        Text("طلب المستفيد حذف هذا الدواء من جدوله. هل توافق على حذفه نهائياً أم ترغب بالاحتفاظ به؟")
                            .dawaiFont(size: 13)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            // Accept: permanently delete from patient
                            Button {
                                withAnimation {
                                    if let caregiver = appState.currentIdentity {
                                        medicationService.approveDeletionRequest(requestId: req.id, by: caregiver)
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash.fill")
                                        .dawaiFont(size: 13, weight: .bold)
                                    Text("قبول وحذف")
                                        .dawaiFont(size: 14, weight: .bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.red.opacity(0.1))
                                .foregroundStyle(Color.red)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            // Reject: keep in patient's schedule
                            Button {
                                withAnimation {
                                    if let caregiver = appState.currentIdentity {
                                        medicationService.rejectDeletionRequest(requestId: req.id, by: caregiver)
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .dawaiFont(size: 13, weight: .bold)
                                    Text("رفض والاحتفاظ")
                                        .dawaiFont(size: 14, weight: .bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(uiColor: .tertiarySystemFill))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(uiColor: .separator).opacity(0.3), lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - 3. Call Button
    @ViewBuilder
    private var callButton: some View {
        Button {
            showingCallAlert = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "phone.fill")
                    .dawaiFont(size: 18, weight: .bold)
                Text("اتصال بالمستفيد")
                    .dawaiFont(size: 18, weight: .bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .foregroundStyle(Color.dawaiPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.dawaiPrimaryBorder, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. Medications Section
    @ViewBuilder
    private var medicationsSection: some View {
        let schedule = currentSchedule
        let patientMedications = currentPatientMedications
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("الادوية")
                    .dawaiFont(size: 22, weight: .bold)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    showingAddMedicationSheet = true
                } label: {
                    Image(systemName: "plus")
                        .dawaiFont(size: 16, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.dawaiPrimary, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("إضافة دواء جديد للمستفيد")
            }

            if schedule.todayDoses.isEmpty && !patientMedications.isEmpty {
                noMedicationsTodayCard
            } else if schedule.remainingDoses == 0 && !schedule.todayDoses.isEmpty {
                // All doses completed state: show all doses of the day at the top with "تم أخذها" or "فائتة" badge
                allDosesCompletedView
            } else if !schedule.activeDoses.isEmpty {
                ForEach(schedule.activeDoses) { dose in
                    activeDoseCard(dose)
                }
            } else {
                emptyMedicationsCard
            }
        }
    }

    // MARK: - All Doses Completed State (Native iOS List)
    @ViewBuilder
    private var allDosesCompletedView: some View {
        let todayDoses = currentSchedule.todayDoses
        let now = medicationService.lastEvaluatedAt
        VStack(spacing: 0) {
            ForEach(todayDoses.indices, id: \.self) { index in
                let dose = todayDoses[index]
                let med = dose.medication
                let state = medicationService.doseInteractionState(
                    for: med,
                    slotMinutes: dose.slotMinutes,
                    at: now,
                    isCarryover: dose.isCarryoverFromYesterday
                )
                let isTakenToday = (state == .taken)
                let itemId = "completed_\(med.id)_\(dose.id)"
                CaregiverSwipeableContainer(
                    itemId: itemId,
                    swipedItemId: $swipedItemId,
                    onEdit: {
                        editingMedication = med
                    },
                    onDelete: {
                        medicationToDelete = med
                        showingCaregiverDeleteAlert = true
                    }
                ) {
                    HStack(spacing: 12) {
                        Button {
                            previewingMedication = med
                        } label: {
                            HStack(spacing: 12) {
                                medicationRowThumbnail(imageData: med.imageData, isTaken: isTakenToday)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(med.name)
                                        .dawaiFont(size: 17, weight: .semibold)
                                        .foregroundStyle(.primary)

                                    Text("\(med.dosage) • \(dose.timeString)")
                                        .dawaiFont(size: 13, weight: .medium)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if state == .missed {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .dawaiFont(size: 11, weight: .bold)
                                Text("فائتة")
                                    .dawaiFont(size: 12, weight: .bold)
                            }
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.10), in: Capsule())
                        } else {
                            Text("تم أخذها")
                                .dawaiFont(size: 12, weight: .bold)
                                .foregroundStyle(Color.dawaiTaken)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color.dawaiTakenBadgeBackground, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                if index < todayDoses.count - 1 {
                    Divider()
                        .padding(.leading, 50)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        Color(uiColor: UIColor { trait in
                            trait.userInterfaceStyle == .dark
                                ? UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.75)
                                : UIColor.white.withAlphaComponent(0.85)
                        })
                    )
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        Color(uiColor: UIColor { trait in
                            trait.userInterfaceStyle == .dark
                                ? UIColor.clear
                                : UIColor(Color.dawaiPrimary).withAlphaComponent(0.025)
                        })
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
        )
    }

    // MARK: - Active Dose Card (Per-Slot Support)
    @ViewBuilder
    private func activeDoseCard(_ dose: ScheduledDose) -> some View {
        let activeMedication = dose.medication
        let now = medicationService.lastEvaluatedAt
        let interactionState = medicationService.doseInteractionState(
            for: activeMedication,
            slotMinutes: dose.slotMinutes,
            at: now,
            isCarryover: dose.isCarryoverFromYesterday
        )
        let isTakenSlot = (interactionState == .taken)
        let itemId = "active_\(dose.id)"

        CaregiverSwipeableContainer(
            itemId: itemId,
            swipedItemId: $swipedItemId,
            onEdit: {
                editingMedication = activeMedication
            },
            onDelete: {
                medicationToDelete = activeMedication
                showingCaregiverDeleteAlert = true
            }
        ) {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Button {
                        previewingMedication = activeMedication
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            medicationHeroThumbnail(imageData: activeMedication.imageData, isTaken: isTakenSlot)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(activeMedication.name)
                                        .dawaiFont(size: 22, weight: .bold)
                                        .foregroundStyle(.primary)

                                    if isTakenSlot {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark")
                                                .dawaiFont(size: 11, weight: .bold)
                                            Text("تم أخذها")
                                                .dawaiFont(size: 12, weight: .bold)
                                        }
                                        .foregroundStyle(Color.dawaiTaken)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.dawaiTakenBadgeBackground, in: Capsule())
                                    }
                                }

                                Text(activeMedication.dosage)
                                    .dawaiFont(size: 15, weight: .medium)
                                    .foregroundStyle(.secondary)

                                Text(dose.timeString)
                                    .dawaiFont(size: 14, weight: .semibold)
                                    .foregroundStyle(
                                        isTakenSlot
                                            ? Color.dawaiTaken
                                            : (interactionState == .overdueLate ? Color.dawaiWarning : Color.dawaiPrimary)
                                    )
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, isTakenSlot ? 16 : 0)

                // Dose Status Banner for Caregiver (Read-only status: "تم أخذها", overdue, or "بانتظار أخذ الجرعة")
                if isTakenSlot {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .dawaiFont(size: 16, weight: .bold)
                        Text("تم أخذها")
                            .dawaiFont(size: 16, weight: .bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.dawaiTakenBadgeBackground)
                    .foregroundStyle(Color.dawaiTaken)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                } else if interactionState == .overdueLate {
                    let mins = medicationService.overdueMinutes(
                        for: activeMedication,
                        slotMinutes: dose.slotMinutes,
                        at: now,
                        isCarryover: dose.isCarryoverFromYesterday
                    ) ?? DoseWindowConfig.lateThresholdMinutes
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .dawaiFont(size: 16, weight: .bold)
                        Text("متأخرة منذ \(mins) دقيقة")
                            .dawaiFont(size: 16, weight: .bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.dawaiWarningBadgeBackground)
                    .foregroundStyle(Color.dawaiWarning)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.fill")
                            .dawaiFont(size: 16, weight: .bold)
                        Text("بانتظار أخذ الجرعة")
                            .dawaiFont(size: 16, weight: .bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.dawaiPrimary.opacity(0.10))
                    .foregroundStyle(Color.dawaiPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                    if isTakenSlot {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.dawaiTakenBackground)
                    } else if interactionState == .overdueLate {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.dawaiWarningBackground.opacity(0.92))
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.dawaiWarning.opacity(0.08))
                    } else {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.dawaiGlassFill)
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.dawaiGlassTint)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        isTakenSlot
                            ? Color.dawaiTakenBorder
                            : (interactionState == .overdueLate ? Color.dawaiWarning.opacity(0.45) : Color.dawaiGlassBorder),
                        lineWidth: (isTakenSlot || interactionState == .overdueLate) ? 1.5 : 1
                    )
            )
        }
    }

    // MARK: - Medication Image Thumbnail Helpers
    @ViewBuilder
    private func medicationHeroThumbnail(imageData: Data?, isTaken: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isTaken ? Color.dawaiTaken : Color.dawaiGlassBorder, lineWidth: isTaken ? 2 : 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isTaken ? Color.dawaiTakenBadgeBackground : Color.dawaiPrimary.opacity(0.12))
                        .frame(width: 68, height: 68)

                    Image(systemName: isTaken ? "checkmark.circle.fill" : "pill.fill")
                        .dawaiFont(size: 32)
                        .foregroundStyle(isTaken ? Color.dawaiTaken : Color.dawaiPrimary)
                        .rotationEffect(isTaken ? .degrees(0) : .degrees(-45))
                }
            }

            if isTaken && imageData != nil {
                Image(systemName: "checkmark.circle.fill")
                    .dawaiFont(size: 18, weight: .bold)
                    .foregroundStyle(.white, Color.dawaiTaken)
                    .offset(x: -4, y: 4)
            }
        }
    }

    @ViewBuilder
    private func medicationRowThumbnail(imageData: Data?, isTaken: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isTaken ? Color.dawaiTaken : Color.dawaiGlassBorder, lineWidth: 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isTaken ? Color.dawaiTakenBadgeBackground : Color.dawaiPrimary.opacity(0.10))
                        .frame(width: 42, height: 42)

                    Image(systemName: isTaken ? "checkmark.circle.fill" : "pill.fill")
                        .dawaiFont(size: 18, weight: .semibold)
                        .foregroundStyle(isTaken ? Color.dawaiTaken : Color.dawaiPrimary)
                        .rotationEffect(isTaken ? .degrees(0) : .degrees(-45))
                }
            }

            if isTaken && imageData != nil {
                Image(systemName: "checkmark.circle.fill")
                    .dawaiFont(size: 14, weight: .bold)
                    .foregroundStyle(.white, Color.dawaiTaken)
                    .offset(x: -3, y: 3)
            }
        }
    }

    // MARK: - Empty Medications Fallback Card
    @ViewBuilder
    private var emptyMedicationsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "pill.fill")
                .dawaiFont(size: 32)
                .foregroundStyle(Color.dawaiPrimary)

            Text("لا توجد أدوية مسجلة")
                .dawaiFont(size: 17, weight: .bold)
                .foregroundStyle(.primary)

            Text("اضغط على (+) في الأعلى لإضافة دواء جديد للمستفيد.")
                .dawaiFont(size: 14)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.dawaiGlassFill)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.dawaiGlassTint)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var noMedicationsTodayCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .dawaiFont(size: 32)
                .foregroundStyle(Color.dawaiPrimary)

            Text("لا توجد أدوية مجدولة لليوم")
                .dawaiFont(size: 17, weight: .bold)
                .foregroundStyle(.primary)

            Text("جميع أدوية المستفيد المسجلة مجدولة في أيام أخرى. اضغط على (+) لإضافة دواء أو لتعديل المواعيد.")
                .dawaiFont(size: 14)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.dawaiGlassFill)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.dawaiGlassTint)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
        )
    }

    // MARK: - 5. Daily Schedule Section (Formerly "باقي اليوم" -> "جدول اليوم")
    @ViewBuilder
    private var upcomingDosesSection: some View {
        let schedule = currentSchedule
        let patientMedications = currentPatientMedications
        // When all doses of the day are taken (remainingDoses == 0), the schedule collapses into "أدويتي" at the top
        if schedule.remainingDoses > 0 && !schedule.upcomingDoses.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("جدول اليوم")
                    .dawaiFont(size: 20, weight: .bold)
                    .foregroundStyle(.primary)

                VStack(spacing: 0) {
                    ForEach(schedule.upcomingDoses.indices, id: \.self) { index in
                        let dose = schedule.upcomingDoses[index]
                        let fullMed = patientMedications.first(where: { $0.id == dose.medicationId })
                        let resolvedSlot = dose.slotMinutes ?? fullMed.map { medicationService.scheduledMinutes(for: $0) }
                        let matchingScheduledDose = schedule.todayDoses.first {
                            $0.medication.id == dose.medicationId && $0.slotMinutes == resolvedSlot
                        }
                        let doseState: MedicationService.DoseInteractionState? = fullMed.map { med in
                            medicationService.doseInteractionState(
                                for: med,
                                slotMinutes: resolvedSlot ?? medicationService.scheduledMinutes(for: med),
                                at: medicationService.lastEvaluatedAt,
                                isCarryover: matchingScheduledDose?.isCarryoverFromYesterday ?? false
                            )
                        }
                        let itemId = "upcoming_\(dose.medicationId)_\(dose.timeString)"
                        CaregiverSwipeableContainer(
                            itemId: itemId,
                            swipedItemId: $swipedItemId,
                            onEdit: {
                                if let med = patientMedications.first(where: { $0.id == dose.medicationId }) {
                                    editingMedication = med
                                } else {
                                    editingMedication = MedicationItem(
                                        id: dose.medicationId,
                                        patientId: beneficiaryPatientId,
                                        name: dose.name,
                                        dosage: dose.dosage,
                                        timeString: dose.timeString,
                                        imageData: dose.imageData
                                    )
                                }
                            },
                            onDelete: {
                                if let med = patientMedications.first(where: { $0.id == dose.medicationId }) {
                                    medicationToDelete = med
                                    showingCaregiverDeleteAlert = true
                                }
                            }
                        ) {
                            HStack(spacing: 12) {
                                Button {
                                    previewingMedication = fullMed ?? MedicationItem(
                                        id: dose.medicationId,
                                        patientId: beneficiaryPatientId,
                                        name: dose.name,
                                        dosage: dose.dosage,
                                        timeString: dose.timeString,
                                        imageData: dose.imageData,
                                        isTaken: dose.isTaken
                                    )
                                } label: {
                                    HStack(spacing: 12) {
                                        medicationRowThumbnail(imageData: dose.imageData ?? fullMed?.imageData, isTaken: dose.isTaken)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(dose.name)
                                                .dawaiFont(size: 17, weight: .semibold)
                                                .foregroundStyle(dose.isTaken ? .secondary : .primary)

                                            Text(dose.dosage)
                                                .dawaiFont(size: 13, weight: .medium)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                if dose.isTaken {
                                    HStack(spacing: 5) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .dawaiFont(size: 13, weight: .bold)
                                        Text("تم أخذها")
                                            .dawaiFont(size: 12, weight: .bold)
                                    }
                                    .foregroundStyle(Color.dawaiTaken)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.dawaiTakenBadgeBackground, in: Capsule())
                                } else if doseState == .overdueLate {
                                    HStack(spacing: 5) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .dawaiFont(size: 11, weight: .bold)
                                        Text("متأخرة • \(dose.timeString)")
                                            .dawaiFont(size: 12, weight: .bold)
                                    }
                                    .foregroundStyle(Color.dawaiWarning)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.dawaiWarningBadgeBackground, in: Capsule())
                                } else if doseState == .missed {
                                    HStack(spacing: 5) {
                                        Image(systemName: "xmark.circle.fill")
                                            .dawaiFont(size: 11, weight: .bold)
                                        Text("فائتة")
                                            .dawaiFont(size: 12, weight: .bold)
                                    }
                                    .foregroundStyle(Color.red)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.red.opacity(0.10), in: Capsule())
                                } else {
                                    HStack(spacing: 5) {
                                        Image(systemName: "clock")
                                            .dawaiFont(size: 12, weight: .semibold)
                                        Text(dose.timeString)
                                            .dawaiFont(size: 13, weight: .semibold)
                                    }
                                    .foregroundStyle(Color.primary.opacity(0.75))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.04), in: Capsule())
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        }

                        if index < schedule.upcomingDoses.count - 1 {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                Color(uiColor: UIColor { trait in
                                    trait.userInterfaceStyle == .dark
                                        ? UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.75)
                                        : UIColor.white.withAlphaComponent(0.85)
                                })
                            )
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                Color(uiColor: UIColor { trait in
                                    trait.userInterfaceStyle == .dark
                                        ? UIColor.clear
                                        : UIColor(Color.dawaiPrimary).withAlphaComponent(0.025)
                                })
                            )
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.dawaiGlassBorder, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - 5.5 As-Needed Medications Section («أدوية عند الحاجة»)
    @ViewBuilder
    private var asNeededMedicationsSection: some View {
        let asNeededMeds = currentPatientMedications.filter {
            $0.scheduleType == .asNeeded && !$0.isPendingDeletion
        }
        if !asNeededMeds.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("أدوية عند الحاجة")
                    .dawaiFont(size: 20, weight: .bold)
                    .foregroundStyle(.primary)

                VStack(spacing: 0) {
                    ForEach(asNeededMeds.indices, id: \.self) { index in
                        let med = asNeededMeds[index]
                        let itemId = "asneeded_\(med.id)"
                        CaregiverSwipeableContainer(
                            itemId: itemId,
                            swipedItemId: $swipedItemId,
                            onEdit: {
                                editingMedication = med
                            },
                            onDelete: {
                                medicationToDelete = med
                                showingCaregiverDeleteAlert = true
                            }
                        ) {
                            HStack(spacing: 12) {
                                Button {
                                    previewingMedication = med
                                } label: {
                                    HStack(spacing: 12) {
                                        medicationRowThumbnail(imageData: med.imageData, isTaken: false)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(med.name)
                                                .dawaiFont(size: 17, weight: .semibold)
                                                .foregroundStyle(.primary)

                                            Text("\(med.dosage) • عند الحاجة (بدون تذكير)")
                                                .dawaiFont(size: 13, weight: .medium)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }

                        if index < asNeededMeds.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }
        }
    }

    // MARK: - 6. Full Medication Photo & Details Preview Sheet
    @ViewBuilder
    private func medicationPreviewSheet(for med: MedicationItem) -> some View {
        let liveMed = currentPatientMedications.first(where: { $0.id == med.id }) ?? med
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let data = liveMed.imageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.dawaiGlassBorder, lineWidth: 1.5)
                            )
                            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.dawaiPrimary.opacity(0.12))
                                .frame(width: 140, height: 140)

                            Image(systemName: "pill.fill")
                                .dawaiFont(size: 56)
                                .foregroundStyle(Color.dawaiPrimary)
                                .rotationEffect(.degrees(-45))
                        }
                        .padding(.top, 12)
                    }

                    VStack(spacing: 8) {
                        Text(liveMed.name)
                            .dawaiFont(size: 28, weight: .bold, design: .rounded)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 10) {
                            HStack(spacing: 5) {
                                Image(systemName: "pills.fill")
                                    .dawaiFont(size: 13)
                                Text(liveMed.dosage.westernNumerals)
                                    .dawaiFont(size: 15, weight: .semibold)
                            }
                            .foregroundStyle(Color.dawaiPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.dawaiPrimary.opacity(0.12), in: Capsule())

                            HStack(spacing: 5) {
                                Image(systemName: "clock.fill")
                                    .dawaiFont(size: 13)
                                Text(liveMed.timeString.westernNumerals)
                                    .dawaiFont(size: 15, weight: .semibold)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
                        }
                    }

                    if let instructions = liveMed.instructions,
                       !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("تعليمات الاستخدام", systemImage: "info.circle.fill")
                                .dawaiFont(size: 14, weight: .bold)
                                .foregroundStyle(Color.dawaiPrimary)

                            Text(instructions)
                                .dawaiFont(size: 15, weight: .medium)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.dawaiGlassFill)
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.dawaiGlassTint)
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dawaiBackground.ignoresSafeArea())
            .navigationTitle("تفاصيل الدواء")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("إغلاق") {
                        previewingMedication = nil
                    }
                    .dawaiFont(size: 16, weight: .semibold)
                    .foregroundStyle(Color.dawaiPrimary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let medToEdit = liveMed
                        previewingMedication = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            editingMedication = medToEdit
                        }
                    } label: {
                        Image(systemName: "pencil")
                            .dawaiFont(size: 16, weight: .bold)
                            .foregroundStyle(Color.dawaiPrimary)
                    }
                    .accessibilityLabel("تعديل الدواء")
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale.dawaiArabic)
    }
}

// MARK: - Caregiver Swipeable Container (Custom Drag Gesture for ScrollView)
private struct CaregiverSwipeableContainer<Content: View>: View {
    let itemId: String
    @Binding var swipedItemId: String?
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var dragOffset: CGFloat = 0
    private let actionButtonsWidth: CGFloat = 130

    private var isOpen: Bool {
        swipedItemId == itemId
    }

    private var currentOffset: CGFloat {
        let base: CGFloat = isOpen ? -actionButtonsWidth : 0
        let total = base + dragOffset
        // Clamp to prevent over-dragging to the right, allow slight rubber-band to the left
        return min(10, max(-actionButtonsWidth - 25, total))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Action Buttons behind the row
            HStack(spacing: 8) {
                Spacer()

                // 1. Delete Button (Red Circle)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        swipedItemId = nil
                        dragOffset = 0
                    }
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .dawaiFont(size: 18, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.red, in: Circle())
                }
                .buttonStyle(.plain)

                // 2. Edit Button (Teal Circle)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        swipedItemId = nil
                        dragOffset = 0
                    }
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .dawaiFont(size: 18, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.dawaiPrimary, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 8)

            // Main Row Content sliding horizontally
            content()
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            Color(uiColor: UIColor { trait in
                                trait.userInterfaceStyle == .dark
                                    ? UIColor.secondarySystemGroupedBackground
                                    : UIColor.white
                            })
                        )
                )
                .offset(x: currentOffset)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .local)
                        .onChanged { value in
                            let hTranslation = value.translation.width
                            let vTranslation = value.translation.height
                            
                            // Only claim if movement is primarily horizontal
                            guard abs(hTranslation) > abs(vTranslation) else { return }

                            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.86)) {
                                if isOpen {
                                    // Moving right closes the swipe
                                    if hTranslation > 0 {
                                        dragOffset = hTranslation
                                    } else {
                                        // Slight resistance when pulling further left
                                        dragOffset = hTranslation * 0.3
                                    }
                                } else {
                                    // Moving left opens the swipe
                                    if hTranslation < 0 {
                                        dragOffset = hTranslation
                                    } else {
                                        // Slight resistance when pulling right while closed
                                        dragOffset = hTranslation * 0.15
                                    }
                                }
                            }
                        }
                        .onEnded { value in
                            let hTranslation = value.translation.width
                            let velocity = value.predictedEndTranslation.width
                            
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                if isOpen {
                                    // If pulled right by 25pt or swiped with velocity, close it
                                    if hTranslation > 25 || velocity > 40 {
                                        swipedItemId = nil
                                    }
                                } else {
                                    // If pulled left by 35pt or flicked left, open it smoothly
                                    if hTranslation < -35 || velocity < -50 {
                                        swipedItemId = itemId
                                    }
                                }
                                dragOffset = 0
                            }
                        }
                )
        }
        .clipped()
    }
}

#Preview {
    NavigationStack {
        CaregiverPatientDetailView(
            beneficiary: BeneficiarySummary(
                name: "عمر",
                hasDelayAlert: true,
                delayNotice: "30 د تأخير",
                scheduledTime: "11:30 م",
                isInvitation: false
            )
        )
    }
    .environmentObject(AppState())
    .tint(Color.dawaiPrimary)
    .environment(\.layoutDirection, .rightToLeft)
}
