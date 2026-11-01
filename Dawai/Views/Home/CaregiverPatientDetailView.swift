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
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var medicationService = MedicationService.shared
    @ObservedObject private var themeService = ThemeService.shared

    @State private var showingCallAlert = false
    @State private var showingReportSheet = false
    @State private var showingAddMedicationSheet = false
    @State private var editingMedication: MedicationItem? = nil

    // UC-11 Direct Deletion by Caregiver
    @State private var medicationToDelete: MedicationItem? = nil
    @State private var showingCaregiverDeleteAlert = false

    public init(beneficiary: BeneficiarySummary) {
        self.beneficiary = beneficiary
    }

    public var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    navigationBarView

                    if beneficiary.hasDelayAlert {
                        delayAlertBanner
                    }

                    // UC-11 Collaborative Approval: Pending Deletion Requests
                    pendingDeletionRequestsSection

                    callButton
                    medicationsSection
                    upcomingDosesSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
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
        }
        .preferredColorScheme(themeService.colorScheme)
        .alert("الاتصال بـ \(beneficiary.name)", isPresented: $showingCallAlert) {
            Button("اتصال هاتفي") {
                let phone = (beneficiary.phoneNumber ?? "0501234567").replacingOccurrences(of: " ", with: "")
                if let url = URL(string: "tel://\(phone)"), UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("يمكنك الاتصال المباشر بالمستفيد للاطمئنان على أخذ الجرعة.")
        }
        .sheet(isPresented: $showingReportSheet) {
            let caregiverUser = appState.currentIdentity ?? UserIdentity(role: .caregiver, displayName: "مقدم الرعاية", keyFingerprint: "cg_default")
            AdherenceReportView(
                currentUser: caregiverUser,
                targetPatientId: beneficiary.id.uuidString,
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
                    .font(.system(size: 18, weight: .bold))
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
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            // Trailing side (LEFT in RTL): Report Sheet button
            Button {
                showingReportSheet = true
            } label: {
                Image(systemName: "doc.text")
                    .font(.system(size: 18, weight: .semibold))
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
        .padding(.top, 8)
    }

    // MARK: - 2. Delay Alert Banner (Refined Warm Amber Alert Card)
    @ViewBuilder
    private var delayAlertBanner: some View {
        let medName = beneficiary.delayedMedicationName ?? medicationService.missedMedicationsToday.first?.name ?? medicationService.activeMedication?.name ?? "الدواء"
        let dosage = beneficiary.delayedDosage ?? medicationService.missedMedicationsToday.first?.dosage ?? "جرعة مجدولة"
        let scheduledTime = beneficiary.scheduledTime ?? medicationService.missedMedicationsToday.first?.timeString ?? "11:30 م"
        let noticeTitle = beneficiary.delayNotice ?? "30 د تأخير، \(medName)"

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.dawaiWarning)

                Text(noticeTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()
            }

            HStack {
                Text("\(dosage)، مجدولة: \(scheduledTime)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.dawaiWarning)

                Spacer()
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.dawaiWarningBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.dawaiWarningBorder, lineWidth: 1.2)
        )
    }

    // MARK: - 2.5 Pending Deletion Requests Section (UC-11 Collaborative Approval)
    @ViewBuilder
    private var pendingDeletionRequestsSection: some View {
        let requests = medicationService.pendingDeletionRequests.filter {
            $0.patientDisplayName == beneficiary.name || $0.patientId == beneficiary.id.uuidString || $0.patientId == "patient_wjd"
        }
        if !requests.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.dawaiWarning)
                    Text("طلبات حذف الأدوية من المستفيد")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                }

                ForEach(requests) { req in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(req.medicationName)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text("\(req.dosage) • \(req.timeString)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "hourglass")
                                    .font(.system(size: 10, weight: .bold))
                                Text("طلب حذف")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(Color.dawaiWarning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.dawaiWarningBackground, in: Capsule())
                        }

                        Text("طلب المستفيد حذف هذا الدواء من جدوله. هل توافق على حذفه نهائياً أم ترغب بالاحتفاظ به؟")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            // Accept: permanently delete from patient
                            Button {
                                withAnimation {
                                    medicationService.approveDeletionRequest(requestId: req.id)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("قبول وحذف")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.red.opacity(0.12))
                                .foregroundStyle(Color.red)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            // Reject: keep in patient's schedule
                            Button {
                                withAnimation {
                                    medicationService.rejectDeletionRequest(requestId: req.id)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("رفض والاحتفاظ")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.dawaiPrimary.opacity(0.12))
                                .foregroundStyle(Color.dawaiPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.dawaiWarningBorder, lineWidth: 1.2)
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
                    .font(.system(size: 18, weight: .bold))
                Text("اتصال بالمستفيد")
                    .font(.system(size: 18, weight: .bold))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("الادوية")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    showingAddMedicationSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.dawaiPrimary, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("إضافة دواء جديد للمستفيد")
            }

            if medicationService.remainingDoses == 0 && !medicationService.medications.isEmpty {
                // All doses completed state: show all medications of the day at the top with "تم أخذها" badge
                allDosesCompletedView
            } else if let activeMedication = medicationService.activeMedication {
                activeMedicationCard(activeMedication)
            } else {
                emptyMedicationsCard
            }
        }
    }

    // MARK: - All Doses Completed State (Native iOS List)
    @ViewBuilder
    private var allDosesCompletedView: some View {
        VStack(spacing: 0) {
            ForEach(medicationService.medications.indices, id: \.self) { index in
                let med = medicationService.medications[index]
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.dawaiTaken)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(med.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("\(med.dosage) • \(med.timeString)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("تم أخذها")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.dawaiTaken)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.dawaiTakenBadgeBackground, in: Capsule())

                    HStack(spacing: 6) {
                        Button {
                            medicationToDelete = med
                            showingCaregiverDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.red)
                                .frame(width: 30, height: 30)
                                .background(Color.red.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("حذف دواء \(med.name)")

                        Button {
                            editingMedication = med
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)
                                .background(Color.black.opacity(0.04), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("تعديل دواء \(med.name)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if index < medicationService.medications.count - 1 {
                    Divider()
                        .padding(.leading, 50)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
        )
    }

    // MARK: - Active Medication Single Card (When Doses Remain)
    @ViewBuilder
    private func activeMedicationCard(_ activeMedication: MedicationItem) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(activeMedication.isTaken ? Color.dawaiTakenBadgeBackground : Color.dawaiPrimary.opacity(0.12))
                        .frame(width: 68, height: 68)

                    Image(systemName: activeMedication.isTaken ? "checkmark.circle.fill" : "pill.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(activeMedication.isTaken ? Color.dawaiTaken : Color.dawaiPrimary)
                        .rotationEffect(activeMedication.isTaken ? .degrees(0) : .degrees(-45))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(activeMedication.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.primary)

                        if activeMedication.isTaken {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                Text("تم أخذها")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(Color.dawaiTaken)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.dawaiTakenBadgeBackground, in: Capsule())
                        }
                    }

                    Text(activeMedication.dosage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(activeMedication.timeString)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(activeMedication.isTaken ? Color.dawaiTaken : Color.dawaiPrimary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        medicationToDelete = activeMedication
                        showingCaregiverDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.red)
                            .frame(width: 32, height: 32)
                            .background(Color.red.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("حذف الدواء للمستفيد")

                    Button {
                        editingMedication = activeMedication
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("تعديل الدواء")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, activeMedication.isTaken ? 16 : 0)

            // Dose Confirmation Action Button (Shown only when NOT taken)
            if !activeMedication.isTaken {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        medicationService.toggleTaken(id: activeMedication.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                        Text("اخذت الدواء")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.dawaiPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(
            activeMedication.isTaken
                ? Color.dawaiTakenBackground
                : Color.clear
        )
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    activeMedication.isTaken ? Color.dawaiTakenBorder : Color.dawaiGlassBorder,
                    lineWidth: activeMedication.isTaken ? 1.5 : 1
                )
        )
    }

    // MARK: - Empty Medications Fallback Card
    @ViewBuilder
    private var emptyMedicationsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "pill.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.dawaiPrimary)

            Text("لا توجد أدوية مسجلة")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)

            Text("اضغط على (+) في الأعلى لإضافة دواء جديد للمستفيد.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
        )
    }

    // MARK: - 5. Daily Schedule Section (Formerly "باقي اليوم" -> "جدول اليوم")
    @ViewBuilder
    private var upcomingDosesSection: some View {
        // When all doses of the day are taken (remainingDoses == 0), the schedule collapses into "أدويتي" at the top
        if medicationService.remainingDoses > 0 && !medicationService.upcomingDoses.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("جدول اليوم")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)

                VStack(spacing: 0) {
                    ForEach(medicationService.upcomingDoses.indices, id: \.self) { index in
                        let dose = medicationService.upcomingDoses[index]
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(dose.name)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(dose.isTaken ? .secondary : .primary)

                                Text(dose.dosage)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if dose.isTaken {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("تم أخذها")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundStyle(Color.dawaiTaken)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color.dawaiTakenBadgeBackground, in: Capsule())
                            } else {
                                HStack(spacing: 5) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(dose.timeString)
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(Color.primary.opacity(0.75))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.04), in: Capsule())
                            }

                            HStack(spacing: 6) {
                                Button {
                                    if let med = medicationService.medications.first(where: { $0.id == dose.id }) {
                                        medicationToDelete = med
                                        showingCaregiverDeleteAlert = true
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.red)
                                        .frame(width: 30, height: 30)
                                        .background(Color.red.opacity(0.08), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("حذف دواء \(dose.name)")

                                Button {
                                    if let med = medicationService.medications.first(where: { $0.id == dose.id }) {
                                        editingMedication = med
                                    } else {
                                        editingMedication = MedicationItem(name: dose.name, dosage: dose.dosage, timeString: dose.timeString)
                                    }
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 30, height: 30)
                                        .background(Color.black.opacity(0.04), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("تعديل دواء \(dose.name)")
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                        if index < medicationService.upcomingDoses.count - 1 {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                )
            }
        }
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
    .tint(Color.dawaiPrimary)
    .environment(\.layoutDirection, .rightToLeft)
}
