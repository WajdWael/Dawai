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

    @State private var activeMedication = HomeMockData.activeMedication
    @State private var upcomingDoses = HomeMockData.upcomingDoses
    @State private var showingCallAlert = false
    @State private var showingReportSheet = false

    public init(beneficiary: BeneficiarySummary) {
        self.beneficiary = beneficiary
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                navigationBarView

                if beneficiary.hasDelayAlert {
                    delayAlertBanner
                }

                callButton
                medicationsSection
                upcomingDosesSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.dawaiBackground.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
        .toolbar(.hidden, for: .navigationBar)
        .alert("الاتصال بـ \(beneficiary.name)", isPresented: $showingCallAlert) {
            Button("اتصال هاتفي") {}
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("يمكنك الاتصال المباشر بالمستفيد للاطمئنان على أخذ الجرعة.")
        }
        .alert("تقرير الجرعات", isPresented: $showingReportSheet) {
            Button("تم", role: .cancel) {}
        } message: {
            Text("سيتم تفعيل سجل تقارير الالتزام الدوائي في المرحلة القادمة.")
        }
    }

    // MARK: - 1. Navigation Bar
    @ViewBuilder
    private var navigationBarView: some View {
        HStack {
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

            Spacer()

            Text(beneficiary.name)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().stroke(Color.dawaiGlassBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    // MARK: - 2. Delay Alert Banner
    @ViewBuilder
    private var delayAlertBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.yellow)

                Text("30 د تأخير، \(activeMedication.name)")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()
            }

            HStack {
                Text("500 مج، مجدولة: \(beneficiary.scheduledTime ?? "11:30 PM")")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))

                Spacer()
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 65.0 / 255.0, green: 68.0 / 255.0, blue: 72.0 / 255.0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
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
                Text("اتصال")
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
                    // Add medication
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.dawaiPrimary, in: Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.dawaiPrimary.opacity(0.12))
                            .frame(width: 68, height: 68)

                        Image(systemName: "pill.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.dawaiPrimary)
                            .rotationEffect(.degrees(-45))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeMedication.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.primary)

                        Text(activeMedication.dosage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(activeMedication.timeString)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.dawaiPrimary)
                    }

                    Spacer()

                    Button {
                        // Edit
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        activeMedication.isTaken.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if activeMedication.isTaken {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                            Text("تم تأكيد الجرعة")
                                .font(.system(size: 18, weight: .bold))
                        } else {
                            Text("اخذت الدواء")
                                .font(.system(size: 18, weight: .bold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(activeMedication.isTaken ? Color.green : Color.dawaiPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.dawaiGlassBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - 5. Upcoming Doses Section
    @ViewBuilder
    private var upcomingDosesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("باقي اليوم")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                ForEach(upcomingDoses.indices, id: \.self) { index in
                    let dose = upcomingDoses[index]
                    HStack {
                        HStack(spacing: 8) {
                            Text(dose.name)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.primary)

                            Text(dose.timeString)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            // Edit
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(
                                    Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)

                    if index < upcomingDoses.count - 1 {
                        Divider()
                            .padding(.horizontal, 14)
                    }
                }
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.dawaiGlassBorder, lineWidth: 1)
            )
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
                scheduledTime: "11:30 PM",
                isInvitation: false
            )
        )
    }
    .tint(Color.dawaiPrimary)
    .environment(\.layoutDirection, .rightToLeft)
}
