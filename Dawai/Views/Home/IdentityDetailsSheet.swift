//
//  IdentityDetailsSheet.swift
//  Dawai
//
//  Settings & Preferences (Role, Appearance, Notifications)
//

import SwiftUI
import UserNotifications

public typealias SettingsSheet = IdentityDetailsSheet

/// Modal sheet for App Settings (Role, Appearance, Notifications)
public struct IdentityDetailsSheet: View {
    let identity: UserIdentity
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var themeService = ThemeService.shared
    @ObservedObject private var demoMode = DemoModeService.shared
    @ObservedObject private var appClock = AppClock.shared
    @ObservedObject private var medicationService = MedicationService.shared
    @State private var notificationsEnabled: Bool = UserDefaults.standard.object(forKey: "dawai_notifications_enabled") as? Bool ?? true
    @State private var showingResetConfirmation = false
    @State private var showingPermissionDeniedAlert = false
    @State private var systemPermissionStatus: UNAuthorizationStatus = .authorized
    @State private var showingReportSheet = false

    public init(identity: UserIdentity) {
        self.identity = identity
    }

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - 1. Role Section (Only the role as requested)
                Section {
                    HStack {
                        Text("الدور")
                            .font(.system(size: 16, weight: .medium))
                        Spacer()
                        Label(identity.role.titleArabic, systemImage: identity.role.systemImage)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.dawaiPrimary)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("الحساب")
                }

                // MARK: - 1.5 Reports Section (UC-7 S#1: Profile Area Access)
                Section {
                    Button {
                        showingReportSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.dawaiPrimary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("تقرير الالتزام الدوائي الأسبوعي")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text("الرسوم البيانية ونسب الالتزام والجرعات")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("التقارير والإحصائيات")
                } footer: {
                    Text("يوفر التقرير الأسبوعي ملخصاً بصرياً لمتابعة انتظام أخذ الجرعات المجدولة.")
                }

                // MARK: - 2. Appearance Section (Dark / Light / System Mode - Backend Connected)
                Section {
                    Picker("المظهر", selection: $themeService.appearanceRaw) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.titleArabic).tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)
                } header: {
                    Text("المظهر")
                } footer: {
                    Text("اختر المظهر الفاتح أو الداكن، أو اجعله يتبع إعدادات الجهاز تلقائياً.")
                }

                // MARK: - 3. Notifications Section (On / Off - Backend & System Connected)
                Section {
                    Toggle(isOn: $notificationsEnabled) {
                        HStack(spacing: 10) {
                            Image(systemName: notificationsEnabled ? "bell.badge.fill" : "bell.slash.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(notificationsEnabled ? Color.dawaiPrimary : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("تنبيهات مواعيد الأدوية")
                                    .font(.system(size: 16, weight: .medium))
                                Text(notificationsEnabled ? "مفعلة" : "متوقفة")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(Color.dawaiPrimary)
                    .onChange(of: notificationsEnabled) { newValue in
                        Task {
                            let result = await MedicationService.shared.setNotificationsEnabled(newValue)
                            switch result {
                            case .permissionDenied:
                                await MainActor.run {
                                    notificationsEnabled = false
                                    showingPermissionDeniedAlert = true
                                    systemPermissionStatus = .denied
                                }
                            case .failed:
                                await MainActor.run {
                                    notificationsEnabled = false
                                }
                            case .enabled:
                                await MainActor.run {
                                    systemPermissionStatus = .authorized
                                }
                            case .disabled:
                                break
                            }
                        }
                    }

                    if systemPermissionStatus == .denied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString),
                               UIApplication.shared.canOpenURL(url) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.dawaiWarning)
                                Text("الإشعارات متوقفة في إعدادات النظام • اضغط لفتح الإعدادات")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.dawaiWarning)
                            }
                        }
                    }
                } header: {
                    Text("الإشعارات")
                } footer: {
                    Text(notificationsEnabled
                         ? "ستصلك تنبيهات صوتية حقيقية عند حلول موعد أخذ كل جرعة دواء مجدولة."
                         : "لن تتلقى أي إشعارات أو تذكيرات عند حلول مواعيد الأدوية.")
                }

                // MARK: - 4. Simulator Tools (Debug & TestFlight only)
                if AppEnvironment.showsSimulatorTools {
                    Section {
                        Button {
                            Task {
                                let fallbackMed = MedicationItem(
                                    patientId: identity.id,
                                    name: "دواء تجريبي",
                                    dosage: "حبة واحدة",
                                    timeString: "12:00 م"
                                )
                                // A caregiver owns no medications; fall back to any medication stored on this device.
                                let med = MedicationService.shared.medications.first
                                    ?? MedicationService.shared.allMedications.first
                                    ?? fallbackMed
                                await MedicationService.shared.simulateInstantMissedDoseAlert(for: med, delaySeconds: 3)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.dawaiWarning)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("محاكاة تنبيه تأخر الجرعة 30 د (UC-5)")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text("إرسال إشعار بعد 3 ثوانٍ لمقدم الرعاية بتأخر الجرعة وتجربة الاتصال")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        #if DEBUG
                        Button {
                            if demoMode.isActive {
                                demoMode.disable()
                            } else {
                                demoMode.enable()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: demoMode.isActive ? "trash.slash.fill" : "tray.and.arrow.down.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.dawaiPrimary)
                                Text(demoMode.isActive ? "إيقاف ومسح البيانات التجريبية (DEBUG)" : "تحميل البيانات التجريبية (DEBUG)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("الساعة الحالية للاختبار (DEBUG)", systemImage: "clock.badge.checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(appClock.isUsingSimulatedTime ? "محاكى" : "ساعة الجهاز")
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        (appClock.isUsingSimulatedTime ? Color.dawaiWarning : Color.secondary)
                                            .opacity(0.15)
                                    )
                                    .foregroundStyle(appClock.isUsingSimulatedTime ? Color.dawaiWarning : Color.secondary)
                                    .clipShape(Capsule())
                            }
                            Text(formattedSimulatedClock)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)

                        if let targetMed = medicationService.activeMedication ?? medicationService.medications.first {
                            Text("الدواء المستهدف: \(targetMed.name) (\(targetMed.timeString.westernNumerals))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)

                            debugStageButton(
                                title: "المرحلة 1: قبل النافذة (-30 د)",
                                subtitle: "يعرض «الجرعة القادمة الساعة \(targetMed.timeString.westernNumerals)»",
                                icon: "clock",
                                tint: .secondary,
                                deltaMinutes: -30,
                                medication: targetMed
                            )
                            debugStageButton(
                                title: "المرحلة 2: داخل النافذة (-10 د)",
                                subtitle: "يفعّل زر «اخذت الدواء» (قبل \(DoseWindowConfig.preWindowMinutes) د من الموعد)",
                                icon: "checkmark.circle",
                                tint: Color.dawaiPrimary,
                                deltaMinutes: -10,
                                medication: targetMed
                            )
                            debugStageButton(
                                title: "المرحلة 3: جرعة متأخرة (+45 د)",
                                subtitle: "يعرض «• جرعة متأخرة» ويبقي زر التأكيد ظاهراً",
                                icon: "exclamationmark.circle.fill",
                                tint: Color.dawaiWarning,
                                deltaMinutes: 45,
                                medication: targetMed
                            )
                            debugStageButton(
                                title: "المرحلة 4: جرعة فائتة (+130 د)",
                                subtitle: "بعد \(DoseWindowConfig.missedCutoffMinutes) د — تسجّل «فائتة» ويختفي الزر",
                                icon: "xmark.octagon.fill",
                                tint: .red,
                                deltaMinutes: 130,
                                medication: targetMed
                            )

                            HStack(spacing: 8) {
                                Button("+15 د") {
                                    appClock.setSimulatedDate(appClock.now.addingTimeInterval(15 * 60))
                                }
                                .buttonStyle(.bordered)
                                Button("+60 د") {
                                    appClock.setSimulatedDate(appClock.now.addingTimeInterval(60 * 60))
                                }
                                .buttonStyle(.bordered)
                                Button("+24 ساعة") {
                                    appClock.setSimulatedDate(appClock.now.addingTimeInterval(24 * 60 * 60))
                                }
                                .buttonStyle(.bordered)
                            }
                            .font(.system(size: 12, weight: .semibold))
                        } else {
                            Text("أضف دواءً واحداً على الأقل لتجربة محاكاة المراحل الأربع للنافذة الزمنية.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        if appClock.isUsingSimulatedTime {
                            Button(role: .destructive) {
                                appClock.reset()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.uturn.backward.circle.fill")
                                    Text("إعادة ضبط الوقت إلى ساعة الجهاز الحقيقية")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            }
                        }
                        #endif
                    } header: {
                        Text("وضع تجريبي")
                    } footer: {
                        Text("تظهر أدوات المحاكاة في نسخ التطوير و TestFlight فقط لتسهيل الاختبار، وتختفي في نسخة App Store.")
                    }
                }

                // MARK: - 5. Reset & Data Management
                Section {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle")
                            Text("إعادة ضبط الهوية")
                        }
                    }
                } header: {
                    Text("إدارة البيانات")
                } footer: {
                    Text("إعادة ضبط الهوية تمسح جميع البيانات المحلية المحفوظة على هذا الجهاز للبدء من جديد.")
                }
            }
            .preferredColorScheme(themeService.colorScheme)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale.dawaiArabic)
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.dawaiPrimary)
                }
            }
            .task {
                let status = await MedicationService.shared.checkSystemNotificationStatus()
                await MainActor.run {
                    systemPermissionStatus = status
                    if status == .denied {
                        notificationsEnabled = false
                    }
                }
            }
            .alert("الإشعارات متوقفة في إعدادات iPhone", isPresented: $showingPermissionDeniedAlert) {
                Button("فتح الإعدادات") {
                    if let url = URL(string: UIApplication.openSettingsURLString),
                       UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("لتلقي تذكيرات بمواعيد أدويتك، يرجى السماح بالإشعارات لتطبيق دواء من إعدادات جهازك.")
            }
            .sheet(isPresented: $showingReportSheet) {
                AdherenceReportView(currentUser: identity)
                    .preferredColorScheme(themeService.colorScheme)
            }
            .confirmationDialog(
                "إعادة ضبط الهوية ومسح جميع البيانات؟",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("مسح جميع البيانات وإعادة الضبط", role: .destructive) {
                    dismiss()
                    appState.resetIdentityAndAllData()
                }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("سيؤدي هذا إلى مسح الهوية الحالية وجميع الأدوية وسجل الالتزام والارتباطات المحفوظة على هذا الجهاز نهائياً، وإعادتك لشاشة البداية.")
            }
        }
        .preferredColorScheme(themeService.colorScheme)
    }

    #if DEBUG
    private var formattedSimulatedClock: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.dawaiArabic
        formatter.dateFormat = "d MMM • hh:mm a"
        return formatter.string(from: appClock.now).westernNumerals
    }

    @ViewBuilder
    private func debugStageButton(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        deltaMinutes: Int,
        medication: MedicationItem
    ) -> some View {
        Button {
            appClock.setStageForMedication(medication, deltaMinutesFromSchedule: deltaMinutes)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    #endif
}

struct IdentityDetailsSheet_Previews: PreviewProvider {
    static var previews: some View {
        IdentityDetailsSheet(
            identity: UserIdentity(
                role: .patient,
                displayName: "بكر",
                keyFingerprint: "e28fa4891b0c9f1a"
            )
        )
        .environmentObject(AppState())
        .tint(Color.dawaiPrimary)
        .environment(\.layoutDirection, .rightToLeft)
    }
}
