//
//  MedicationFormView.swift
//  Dawai
//
//  Use-Case 3 (UC-3) Add / Edit Medication Form
//  Implements Mockup Screens 1, 2, 3, 4, 5:
//  Screen 1: Main Medication Entry Form ("إضافة الدواء" / "تعديل الدواء")
//  Screen 2: Dose Time Configuration ("اضف وقت الجرعة")
//  Screen 3: Duration Selection ("المدة")
//  Screen 4: Days Selection ("الايام")
//  Screen 5: Frequency Selection ("التكرار خلال اليوم")
//

import SwiftUI

public enum MedicationFormMode {
    case add
    case edit(MedicationItem)

    public var title: String {
        switch self {
        case .add: return "إضافة الدواء"
        case .edit: return "تعديل الدواء"
        }
    }

    public var isEditing: Bool {
        if case .edit = self { return true }
        return false
    }
}

public enum MedicationSubscreen {
    case main
    case doseTime
    case duration
    case days
    case frequency
}

public struct MedicationFormView: View {
    public let mode: MedicationFormMode
    public let currentUser: UserIdentity
    public var targetPatient: BeneficiarySummary?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var medicationService = MedicationService.shared

    private var fieldBackground: Color {
        colorScheme == .dark
            ? Color(red: 30/255, green: 33/255, blue: 38/255)
            : Color(red: 238/255, green: 240/255, blue: 244/255)
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 26/255, green: 28/255, blue: 32/255)
            : Color.white
    }

    // Navigation Subscreen State
    @State private var currentSubscreen: MedicationSubscreen = .main

    // Form Inputs
    @State private var name: String = ""
    @State private var dosage: String = ""
    @State private var selectedTime: Date = Date()
    @State private var hasConfiguredTime: Bool = false
    @State private var selectedDays: [String] = ["كل يوم"]
    @State private var selectedFrequency: String = "مرة يوميًا"
    @State private var customFrequencyText: String = ""
    @State private var selectedDuration: String = "دائم"
    @State private var customDurationValue: String = ""
    @State private var customDurationUnit: String = "شهر"
    @State private var instructions: String = ""
    @State private var imageData: Data? = nil

    // UI & Validation State
    @State private var errorMessage: String? = nil
    @State private var showingCameraView: Bool = false
    @State private var showingDeleteAlert: Bool = false
    @State private var isSaving: Bool = false

    public init(
        mode: MedicationFormMode = .add,
        currentUser: UserIdentity,
        targetPatient: BeneficiarySummary? = nil
    ) {
        self.mode = mode
        self.currentUser = currentUser
        self.targetPatient = targetPatient
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(red: 16/255, green: 18/255, blue: 22/255) : Color(red: 247/255, green: 248/255, blue: 250/255))
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header Bar (Custom across all 5 screens)
                    headerBarView

                    // Error Banner if validation fails (UC-3 Alternate Course)
                    if let err = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                            Text(err)
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color.red.opacity(0.85))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Content based on active subscreen
                    ScrollView {
                        VStack(spacing: 20) {
                            switch currentSubscreen {
                            case .main:
                                mainFormContent
                            case .doseTime:
                                doseTimeContent
                            case .duration:
                                durationContent
                            case .days:
                                daysContent
                            case .frequency:
                                frequencyContent
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 36)
                    }
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .onAppear(perform: initializeFormValues)
            .fullScreenCover(isPresented: $showingCameraView) {
                MedicationCameraView(capturedImageData: $imageData)
            }
            .alert("حذف الدواء", isPresented: $showingDeleteAlert) {
                Button("حذف", role: .destructive) {
                    if case .edit(let existing) = mode {
                        medicationService.deleteMedication(id: existing.id)
                        dismiss()
                    }
                }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("هل أنت متأكد من رغبتك في حذف هذا الدواء؟ سيتم إلغاء جميع التذكيرات المرتبطة به.")
            }
        }
    }

    // MARK: - Initializer for Edit Mode
    private func initializeFormValues() {
        if case .edit(let item) = mode {
            self.name = item.name
            self.dosage = item.dosage
            self.selectedTime = item.scheduledDate ?? Date()
            self.hasConfiguredTime = true
            self.selectedDays = item.days.isEmpty ? ["كل يوم"] : item.days
            
            let standardFrequencies = ["مرة يوميًا", "كل 4 ساعات", "كل 6 ساعات", "كل 8 ساعات", "كل 12 ساعة"]
            if standardFrequencies.contains(item.frequency) {
                self.selectedFrequency = item.frequency
            } else {
                self.selectedFrequency = "حسب أيام محددة\\أوقات محددة"
                self.customFrequencyText = item.frequency
            }

            self.selectedDuration = item.duration
            self.instructions = item.instructions ?? ""
            self.imageData = item.imageData
        }
    }

    // MARK: - 1. Custom Header Bar
    private var headerBarView: some View {
        HStack {
            // Close / Back Button ('X')
            Button {
                handleDismissOrBack()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            // Screen Title
            Text(currentHeaderTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()

            // Save / Confirm Checkmark Button
            Button {
                handleConfirmOrSave()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.dawaiPrimary)
                        .frame(width: 36, height: 36)

                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(colorScheme == .dark ? Color(red: 24/255, green: 26/255, blue: 30/255) : Color.white)
        .overlay(
            Divider(), alignment: .bottom
        )
    }

    private var currentHeaderTitle: String {
        switch currentSubscreen {
        case .main:
            return mode.title
        case .doseTime:
            return "اضف وقت الجرعة"
        case .duration:
            return "المدة"
        case .days:
            return "الايام"
        case .frequency:
            return "التكرار خلال اليوم"
        }
    }

    private func handleDismissOrBack() {
        switch currentSubscreen {
        case .main:
            dismiss()
        case .doseTime:
            currentSubscreen = .main
        case .duration, .days, .frequency:
            currentSubscreen = .doseTime
        }
    }

    private func handleConfirmOrSave() {
        switch currentSubscreen {
        case .main:
            saveMedication()
        case .doseTime:
            hasConfiguredTime = true
            currentSubscreen = .main
        case .duration, .days, .frequency:
            currentSubscreen = .doseTime
        }
    }

    // MARK: - 2. Screen 1: Main Form Content
    private var mainFormContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Field 1: اسم الدواء
            VStack(alignment: .leading, spacing: 8) {
                Text("اسم الدواء")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                TextField("ميتروفين", text: $name)
                    .font(.system(size: 16))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Field 2: الجرعة
            VStack(alignment: .leading, spacing: 8) {
                Text("الجرعة")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                TextField("نص حبه - حبتين، 10 مل", text: $dosage)
                    .font(.system(size: 16))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Field 3: مواعيد تناول الدواء
            VStack(alignment: .leading, spacing: 8) {
                Text("مواعيد تناول الدواء")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                if hasConfiguredTime {
                    // Configured schedule summary chip
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(timeFormatter.string(from: selectedTime))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Color.dawaiPrimary)

                            Text("\(selectedFrequencySummary) • \(selectedDays.joined(separator: "، ")) • \(selectedDurationSummary)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentSubscreen = .doseTime
                            }
                        } label: {
                            Text("تعديل")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.dawaiPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.dawaiPrimary.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.dawaiPrimary.opacity(0.3), lineWidth: 1)
                    )
                }

                // Add Time Button (+ اضف وقت)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentSubscreen = .doseTime
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("+ اضف وقت")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Field 4: تعليمات إضافية
            VStack(alignment: .leading, spacing: 8) {
                Text("تعليمات إضافية")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                TextField("مثال: بعد الإفطار", text: $instructions)
                    .font(.system(size: 16))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Field 5: صورة الدواء
            VStack(alignment: .leading, spacing: 8) {
                Text("صورة الدواء")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                if let data = imageData, let uiImage = UIImage(data: data) {
                    // Preview of attached image
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 140)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // Remove image button
                        Button {
                            withAnimation {
                                self.imageData = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white, Color.black.opacity(0.6))
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // Empty Camera Box
                    Button {
                        showingCameraView = true
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "camera.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.black.opacity(0.6))
                            Spacer()
                        }
                        .frame(height: 72)
                        .background(fieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Field 6: حذف الدواء (When editing)
            if mode.isEditing {
                Button {
                    showingDeleteAlert = true
                } label: {
                    HStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "trash.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("حذف الدواء")
                            .font(.system(size: 16, weight: .bold))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 15)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.red.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
        }
    }

    // MARK: - 3. Screen 2: Dose Time Content ("اضف وقت الجرعة")
    private var doseTimeContent: some View {
        VStack(spacing: 20) {
            // iOS Glass Mode Wheel Time Picker Card
            ZStack {
                // Subtle ambient glow behind the glass to create refraction depth in both Light & Dark modes
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.dawaiPrimary.opacity(colorScheme == .dark ? 0.22 : 0.12),
                                Color.dawaiPrimary.opacity(colorScheme == .dark ? 0.06 : 0.03),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: 8)

                // Frosted glass wheel container
                VStack {
                    DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    // Specular glass shine & rim lighting
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.45 : 0.9),
                                    Color.white.opacity(colorScheme == .dark ? 0.12 : 0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(
                    color: colorScheme == .dark ? Color.black.opacity(0.35) : Color.dawaiPrimary.opacity(0.08),
                    radius: 14,
                    x: 0,
                    y: 6
                )
            }

            // 3 Navigation Rows
            VStack(spacing: 12) {
                // Row 1: الايام
                scheduleNavigationRow(
                    title: "الايام",
                    value: selectedDays.joined(separator: "، ")
                ) {
                    currentSubscreen = .days
                }

                // Row 2: التكرار خلال اليوم
                scheduleNavigationRow(
                    title: "التكرار خلال اليوم",
                    value: selectedFrequencySummary
                ) {
                    currentSubscreen = .frequency
                }

                // Row 3: المدة
                scheduleNavigationRow(
                    title: "المدة",
                    value: selectedDurationSummary
                ) {
                    currentSubscreen = .duration
                }
            }
        }
    }

    private func scheduleNavigationRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(value)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. Screen 3: Duration Content ("المدة")
    private let durationOptions = [
        "3 ايام",
        "اسبوع",
        "3 اسابيع",
        "4 اسابيع",
        "دائم"
    ]

    private var durationContent: some View {
        VStack(spacing: 10) {
            ForEach(durationOptions, id: \.self) { option in
                selectionOptionRow(
                    title: option,
                    isSelected: selectedDuration == option
                ) {
                    selectedDuration = option
                }
            }

            // Custom "اخرى (ارقام فقط)"
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("اخرى (ارقام فقط)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)

                    Spacer()

                    if selectedDuration == "اخرى" {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.dawaiPrimary)
                    }
                }

                if selectedDuration == "اخرى" {
                    HStack(spacing: 12) {
                        TextField("مثال: 10", text: $customDurationValue)
                            .keyboardType(.numberPad)
                            .font(.system(size: 15))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Menu {
                            Button("يوم") { customDurationUnit = "يوم" }
                            Button("اسبوع") { customDurationUnit = "اسبوع" }
                            Button("شهر") { customDurationUnit = "شهر" }
                        } label: {
                            HStack {
                                Text(customDurationUnit)
                                    .font(.system(size: 15, weight: .bold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(Color.dawaiPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture {
                selectedDuration = "اخرى"
            }
        }
    }

    private var selectedDurationSummary: String {
        if selectedDuration == "اخرى" {
            let val = customDurationValue.isEmpty ? "1" : customDurationValue
            return "\(val) \(customDurationUnit)"
        }
        return selectedDuration
    }

    // MARK: - 5. Screen 4: Days Content ("الايام")
    private let dayOptions = [
        "كل يوم",
        "كل الاحد",
        "كل الاثنين",
        "كل الثلاثاء",
        "كل الاربعاء",
        "كل الخميس",
        "كل الجمعه",
        "كل السبت"
    ]

    private var daysContent: some View {
        VStack(spacing: 10) {
            ForEach(dayOptions, id: \.self) { day in
                selectionOptionRow(
                    title: day,
                    isSelected: selectedDays.contains(day)
                ) {
                    toggleDay(day)
                }
            }
        }
    }

    private func toggleDay(_ day: String) {
        if day == "كل يوم" {
            selectedDays = ["كل يوم"]
        } else {
            selectedDays.removeAll { $0 == "كل يوم" }
            if selectedDays.contains(day) {
                selectedDays.removeAll { $0 == day }
                if selectedDays.isEmpty {
                    selectedDays = ["كل يوم"]
                }
            } else {
                selectedDays.append(day)
            }
        }
    }

    // MARK: - 6. Screen 5: Frequency Content ("التكرار خلال اليوم")
    private let standardFrequencyOptions = [
        "مرة يوميًا",
        "كل 4 ساعات",
        "كل 6 ساعات",
        "كل 8 ساعات",
        "كل 12 ساعة"
    ]

    private var isCustomFrequencySelected: Bool {
        selectedFrequency == "حسب أيام محددة\\أوقات محددة"
    }

    private var frequencyContent: some View {
        VStack(spacing: 12) {
            ForEach(standardFrequencyOptions, id: \.self) { freq in
                selectionOptionRow(
                    title: freq,
                    isSelected: selectedFrequency == freq
                ) {
                    selectedFrequency = freq
                }
            }

            // The last option: iOS Dropdown Menu for "حسب أيام محددة\أوقات محددة"
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("حسب أيام محددة\\أوقات محددة")
                        .font(.system(size: 16, weight: isCustomFrequencySelected ? .bold : .medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    // Native iOS Dropdown Menu
                    Menu {
                        Section("التكرار اليومي") {
                            Button {
                                selectCustomFrequencyPreset("مرتان يومياً")
                            } label: {
                                HStack {
                                    Text("مرتان يومياً")
                                    if customFrequencyText == "مرتان يومياً" {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Button {
                                selectCustomFrequencyPreset("3 مرات يومياً")
                            } label: {
                                HStack {
                                    Text("3 مرات يومياً")
                                    if customFrequencyText == "3 مرات يومياً" {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Button {
                                selectCustomFrequencyPreset("4 مرات يومياً")
                            } label: {
                                HStack {
                                    Text("4 مرات يومياً")
                                    if customFrequencyText == "4 مرات يومياً" {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }

                        Section("أيام محددة وفترات") {
                            Button {
                                selectCustomFrequencyPreset("كل يومين")
                            } label: {
                                HStack {
                                    Text("كل يومين")
                                    if customFrequencyText == "كل يومين" {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Button {
                                selectCustomFrequencyPreset("كل 3 أيام")
                            } label: {
                                HStack {
                                    Text("كل 3 أيام")
                                    if customFrequencyText == "كل 3 أيام" {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Button {
                                selectCustomFrequencyPreset("أسبوعياً")
                            } label: {
                                HStack {
                                    Text("أسبوعياً")
                                    if customFrequencyText == "أسبوعياً" {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Button {
                                selectCustomFrequencyPreset("شهرياً")
                            } label: {
                                HStack {
                                    Text("شهرياً")
                                    if customFrequencyText == "شهرياً" {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }

                        Section("حسب الحاجة والمواعيد") {
                            Button {
                                selectCustomFrequencyPreset("عند اللزوم / الحاجة")
                            } label: {
                                HStack {
                                    Text("عند اللزوم / الحاجة")
                                    if customFrequencyText == "عند اللزوم / الحاجة" {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Button {
                                selectCustomFrequencyPreset("قبل النوم")
                            } label: {
                                HStack {
                                    Text("قبل النوم")
                                    if customFrequencyText == "قبل النوم" {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Button {
                                selectCustomFrequencyPreset("مع الوجبات")
                            } label: {
                                HStack {
                                    Text("مع الوجبات")
                                    if customFrequencyText == "مع الوجبات" {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Button {
                                selectCustomFrequencyPreset("على الريق")
                            } label: {
                                HStack {
                                    Text("على الريق")
                                    if customFrequencyText == "على الريق" {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }

                        Section("إدخال مخصص") {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedFrequency = "حسب أيام محددة\\أوقات محددة"
                                }
                            } label: {
                                Label("كتابة تكرار يدوي...", systemImage: "square.and.pencil")
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(customFrequencyMenuTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.dawaiPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.dawaiPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFrequency = "حسب أيام محددة\\أوقات محددة"
                    }
                }

                // Custom Data Entry Field (when selected)
                if isCustomFrequencySelected {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("أو أدخل التكرار يدوياً:")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField("مثال: 3 مرات يومياً، كل يومين، بعد الأكل", text: $customFrequencyText)
                                .font(.system(size: 15))

                            if !customFrequencyText.isEmpty {
                                Button {
                                    customFrequencyText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.dawaiPrimary.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func selectCustomFrequencyPreset(_ preset: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            self.selectedFrequency = "حسب أيام محددة\\أوقات محددة"
            self.customFrequencyText = preset
        }
    }

    private var customFrequencyMenuTitle: String {
        let trimmed = customFrequencyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return isCustomFrequencySelected ? "اختر التكرار" : "خيارات التكرار"
    }

    private var selectedFrequencySummary: String {
        if selectedFrequency == "حسب أيام محددة\\أوقات محددة" {
            let trimmed = customFrequencyText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "حسب أيام محددة\\أوقات محددة" : trimmed
        }
        return selectedFrequency
    }

    private func selectionOptionRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.dawaiPrimary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Form Submission & Validation (UC-3 S#4 & Alternate Courses)
    private func saveMedication() {
        errorMessage = nil
        isSaving = true

        Task {
            do {
                let timeStr = timeFormatter.string(from: selectedTime)
                let durationFinal = selectedDurationSummary
                let freqFinal = selectedFrequencySummary

                switch mode {
                case .add:
                    let newMedication = MedicationItem(
                        name: name,
                        dosage: dosage,
                        timeString: timeStr,
                        scheduledDate: selectedTime,
                        days: selectedDays,
                        frequency: freqFinal,
                        duration: durationFinal,
                        instructions: instructions.isEmpty ? nil : instructions,
                        imageData: imageData,
                        isTaken: false
                    )

                    try await medicationService.addMedication(
                        item: newMedication,
                        currentUser: currentUser,
                        targetPatientId: targetPatient?.id.uuidString
                    )

                case .edit(let existing):
                    var updated = existing
                    updated.name = name
                    updated.dosage = dosage
                    updated.timeString = timeStr
                    updated.scheduledDate = selectedTime
                    updated.days = selectedDays
                    updated.frequency = freqFinal
                    updated.duration = durationFinal
                    updated.instructions = instructions.isEmpty ? nil : instructions
                    updated.imageData = imageData

                    try await medicationService.updateMedication(
                        item: updated,
                        currentUser: currentUser,
                        targetPatientId: targetPatient?.id.uuidString
                    )
                }

                isSaving = false
                dismiss()
            } catch let error as MedicationError {
                isSaving = false
                withAnimation {
                    self.errorMessage = error.localizedDescription
                }
            } catch {
                isSaving = false
                withAnimation {
                    self.errorMessage = "حدث خطأ غير متوقع أثناء حفظ الدواء."
                }
            }
        }
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar_SA")
        formatter.dateFormat = "hh:mm a"
        return formatter
    }
}
