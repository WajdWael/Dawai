//
//  IdentityDetailsSheet.swift
//  Dawai
//
//  Settings & Preferences (Role, CloudKit Sync, Appearance, Text Size, Notifications)
//

import SwiftUI
import UserNotifications

public typealias SettingsSheet = IdentityDetailsSheet

/// Modal sheet for App Settings
public struct IdentityDetailsSheet: View {
    let identity: UserIdentity
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var themeService = ThemeService.shared
    @ObservedObject private var cloudSync = CloudKitSyncManager.shared
    @State private var notificationsEnabled: Bool = UserDefaults.standard.object(forKey: "dawai_notifications_enabled") as? Bool ?? true
    @State private var alarmKitEnabled: Bool = MedicationAlarmService.shared.isUserEnabled
    @State private var liveActivityEnabled: Bool = DoseLiveActivityManager.shared.isUserEnabled
    @State private var showingPermissionDeniedAlert = false
    @State private var showingAlarmPermissionDeniedAlert = false
    @State private var showingResetConfirmAlert = false
    @State private var systemPermissionStatus: UNAuthorizationStatus = .authorized

    public init(identity: UserIdentity) {
        self.identity = identity
    }

    private var textSizeSliderBinding: Binding<Double> {
        Binding(
            get: { Double(themeService.textSizeStep) },
            set: { newValue in
                let rounded = Int(newValue.rounded())
                if themeService.textSizeStep != rounded {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    themeService.textSizeStep = rounded
                }
            }
        )
    }

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - 1. Role Section (Current Role Only)
                Section {
                    HStack {
                        Text("الدور الحالي")
                            .dawaiFont(size: 16, weight: .medium)
                        Spacer()
                        Label("\(identity.displayName) • \(identity.role.titleArabic)", systemImage: identity.role.systemImage)
                            .dawaiFont(size: 15, weight: .bold)
                            .foregroundStyle(Color.dawaiPrimary)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("الحساب")
                }

                // MARK: - 2. CloudKit Sync Section
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: cloudSync.isAccountAvailable ? "icloud.and.arrow.up.fill" : "icloud.slash.fill")
                            .dawaiFont(size: 18)
                            .foregroundStyle(cloudSync.isAccountAvailable ? Color.dawaiPrimary : .orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(cloudSync.statusMessage)
                                .dawaiFont(size: 14, weight: .semibold)
                                .foregroundStyle(.primary)

                            if let lastSynced = cloudSync.lastSyncedAt {
                                Text("آخر مزامنة: \(lastSynced.formatted(date: .omitted, time: .shortened))")
                                    .dawaiFont(size: 12)
                                    .foregroundStyle(.secondary)
                            } else if cloudSync.pendingUploadCount > 0 {
                                Text("بانتظار رفع \(cloudSync.pendingUploadCount) تحديثات")
                                    .dawaiFont(size: 12)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if cloudSync.isSyncing {
                            ProgressView()
                        }
                    }

                    Button {
                        Task {
                            await cloudSync.syncNow(silent: false)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(Color.dawaiPrimary)
                            Text("مزامنة الآن مع iCloud")
                                .dawaiFont(size: 15, weight: .semibold)
                                .foregroundStyle(Color.dawaiPrimary)
                        }
                    }
                    .disabled(cloudSync.isSyncing)
                } header: {
                    Text("المزامنة السحابية (iCloud)")
                }

                // MARK: - 3. Appearance & iOS-Style Text Size Section
                Section {
                    Picker("المظهر", selection: $themeService.appearanceRaw) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.titleArabic).tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("حجم الخط", systemImage: "textformat.size")
                                .dawaiFont(size: 16, weight: .medium)
                            Spacer()
                            Text(themeService.currentTextSize.titleArabic)
                                .dawaiFont(size: 14, weight: .bold)
                                .foregroundStyle(Color.dawaiPrimary)
                        }

                        // Native iOS-style Text Size slider with small/large glyph anchors & step ticks
                        VStack(spacing: 4) {
                            HStack(spacing: 14) {
                                Text("أ")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                Slider(
                                    value: textSizeSliderBinding,
                                    in: Double(AppTextSize.small.rawValue)...Double(AppTextSize.maximum.rawValue),
                                    step: 1
                                )
                                .tint(Color.dawaiPrimary)
                                .accessibilityLabel("حجم الخط")
                                .accessibilityValue(themeService.currentTextSize.titleArabic)

                                Text("أ")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.primary)
                            }

                            // Step tick indicators matching iOS Display & Brightness -> Text Size
                            HStack {
                                ForEach(AppTextSize.allCases) { step in
                                    Capsule()
                                        .fill(
                                            step.rawValue == themeService.textSizeStep
                                                ? Color.dawaiPrimary
                                                : Color.secondary.opacity(0.35)
                                        )
                                        .frame(width: step.rawValue == themeService.textSizeStep ? 3 : 2, height: step.rawValue == themeService.textSizeStep ? 10 : 7)
                                    if step != AppTextSize.allCases.last {
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.horizontal, 34)
                        }

                        Text("معاينة حجم النص في مواعيد أدويتك وتنبيهات الجرعات.")
                            .dawaiFont(size: 15, weight: .medium)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("المظهر وحجم الخط")
                }

                // MARK: - 4. Notifications Section (On / Off - Backend & System Connected)
                Section {
                    Toggle(isOn: $notificationsEnabled) {
                        HStack(spacing: 10) {
                            Image(systemName: notificationsEnabled ? "bell.badge.fill" : "bell.slash.fill")
                                .dawaiFont(size: 18)
                                .foregroundStyle(notificationsEnabled ? Color.dawaiPrimary : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("تنبيهات مواعيد الأدوية")
                                    .dawaiFont(size: 16, weight: .medium)
                                Text(notificationsEnabled ? "مفعلة" : "متوقفة")
                                    .dawaiFont(size: 12)
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

                    if MedicationAlarmService.shared.isSupportedOnDevice && notificationsEnabled {
                        Toggle(isOn: $alarmKitEnabled) {
                            HStack(spacing: 10) {
                                Image(systemName: alarmKitEnabled ? "alarm.waves.left.and.right.fill" : "alarm")
                                    .dawaiFont(size: 18)
                                    .foregroundStyle(alarmKitEnabled ? Color.dawaiPrimary : .secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("منبّه الدواء القوي (ملء الشاشة)")
                                        .dawaiFont(size: 16, weight: .medium)
                                    Text("يرن بملء الشاشة ويتجاوز الصامت بدون غفوة")
                                        .dawaiFont(size: 12)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(Color.dawaiPrimary)
                        .onChange(of: alarmKitEnabled) { newValue in
                            Task {
                                let ok = await MedicationService.shared.setAlarmKitEnabled(newValue)
                                if newValue && !ok {
                                    await MainActor.run {
                                        alarmKitEnabled = false
                                        showingAlarmPermissionDeniedAlert = true
                                    }
                                }
                            }
                        }
                    }

                    if notificationsEnabled && identity.role == .patient {
                        Toggle(isOn: $liveActivityEnabled) {
                            HStack(spacing: 10) {
                                Image(systemName: liveActivityEnabled ? "platter.filled.top.iphone" : "iphone")
                                    .dawaiFont(size: 18)
                                    .foregroundStyle(liveActivityEnabled ? Color.dawaiPrimary : .secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("تنبيهات Dynamic Island وشاشة القفل")
                                        .dawaiFont(size: 16, weight: .medium)
                                    Text("يعرض الجرعة القادمة والمتأخرة في الجزيرة التفاعلية")
                                        .dawaiFont(size: 12)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(Color.dawaiPrimary)
                        .onChange(of: liveActivityEnabled) { newValue in
                            DoseLiveActivityManager.shared.isUserEnabled = newValue
                            if newValue {
                                DoseLiveActivityManager.shared.sync(using: MedicationService.shared)
                            } else {
                                DoseLiveActivityManager.shared.endAllActivities()
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
                                    .dawaiFont(size: 12, weight: .semibold)
                                    .foregroundStyle(Color.dawaiWarning)
                            }
                        }
                    }
                } header: {
                    Text("الإشعارات")
                }

                // MARK: - 4.5 Testing / Demo Simulation Section
                Section {
                    Toggle(isOn: Binding(
                        get: { DemoModeService.shared.isActive },
                        set: { isEnabled in
                            if isEnabled {
                                DemoModeService.shared.enable()
                            } else {
                                DemoModeService.shared.disable()
                            }
                        }
                    )) {
                        HStack(spacing: 10) {
                            Image(systemName: "wand.and.stars")
                                .dawaiFont(size: 18)
                                .foregroundStyle(Color.dawaiPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("محاكاة بيانات تجريبية (Demo Mode)")
                                    .dawaiFont(size: 16, weight: .medium)
                                Text("توليد أدوية وجرعات وتقارير جاهزة للاختبار والمعاينة")
                                    .dawaiFont(size: 12)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(Color.dawaiPrimary)
                } header: {
                    Text("أدوات التجربة والاختبار")
                }

                // MARK: - 5. Sign Out & Wipe Section
                Section {
                    Button(role: .destructive) {
                        showingResetConfirmAlert = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.red)
                            Text("تسجيل الخروج وحذف البيانات")
                                .dawaiFont(size: 16, weight: .bold)
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                } footer: {
                    Text("سيؤدي تسجيل الخروج إلى مسح جميع الأدوية وسجلات الجرعات والارتباطات المحفوظة محلياً على هذا الجهاز والعودة إلى شاشة البداية.")
                }
            }
            .preferredColorScheme(themeService.colorScheme)
            .environment(\.dawaiFontScale, themeService.fontScale)
            .environment(\.dynamicTypeSize, themeService.dynamicTypeSize)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale.dawaiArabic)
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("إغلاق") {
                        dismiss()
                    }
                    .dawaiFont(size: 16, weight: .semibold)
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
            .alert("إذن المنبّهات متوقف في إعدادات iPhone", isPresented: $showingAlarmPermissionDeniedAlert) {
                Button("فتح الإعدادات") {
                    if let url = URL(string: UIApplication.openSettingsURLString),
                       UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("لتشغيل منبّه الدواء القوي بملء الشاشة، يرجى السماح بإذن المنبّهات لتطبيق دواء من إعدادات الجهاز.")
            }
            .alert("تسجيل الخروج وحذف البيانات", isPresented: $showingResetConfirmAlert) {
                Button("تسجيل الخروج وحذف البيانات", role: .destructive) {
                    dismiss()
                    appState.resetIdentityAndAllData()
                }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("هل أنت متأكد من رغبتك في تسجيل الخروج؟ سيتم مسح كافة الأدوية وسجلات الجرعات والارتباطات المحفوظة على هذا الجهاز والعودة إلى شاشة البداية.")
            }
        }
        .environment(\.dawaiFontScale, themeService.fontScale)
        .environment(\.dynamicTypeSize, themeService.dynamicTypeSize)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale.dawaiArabic)
        .preferredColorScheme(themeService.colorScheme)
    }
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
