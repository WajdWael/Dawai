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
    public var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var medicationService = MedicationService.shared
    @ObservedObject private var themeService = ThemeService.shared

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
        targetPatient: BeneficiarySummary? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.currentUser = currentUser
        self.targetPatient = targetPatient
        self.onDismiss = onDismiss
    }

    @MainActor
    private func closeForm() {
        dismiss()
        onDismiss?()
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
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
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 36)
                    }
                }
            }
            .navigationTitle(currentHeaderTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        handleDismissOrBack()
                    } label: {
                        if currentSubscreen == .main {
                            Text("إلغاء")
                                .font(.system(size: 17, weight: .regular))
                        } else {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.backward")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(currentSubscreen == .doseTime ? "إلغاء" : "رجوع")
                                    .font(.system(size: 17, weight: .regular))
                            }
                        }
                    }
                    .foregroundStyle(Color.dawaiPrimary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        handleConfirmOrSave()
                    } label: {
                        Text(currentSubscreen == .main ? "حفظ" : "تم")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(Color.dawaiPrimary)
                    .disabled(isSaving)
                }
            }
            .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .preferredColorScheme(themeService.colorScheme)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale.dawaiArabic)
            .onAppear(perform: initializeFormValues)
            .fullScreenCover(isPresented: $showingCameraView) {
                MedicationCameraView(capturedImageData: $imageData)
            }
            .alert("حذف الدواء", isPresented: $showingDeleteAlert) {
                Button(
                    currentUser.role == .caregiver || RelationshipService.shared.activeRelationships.isEmpty
                        ? "حذف"
                        : "إرسال طلب الحذف",
                    role: .destructive
                ) {
                    if case .edit(let existing) = mode {
                        if currentUser.role == .caregiver {
                            medicationService.deleteMedicationByCaregiver(id: existing.id, patientName: targetPatient?.name)
                        } else if RelationshipService.shared.activeRelationships.isEmpty {
                            medicationService.deleteMedicationDirectly(id: existing.id)
                        } else {
                            medicationService.requestMedicationDeletionByPatient(
                                medicationId: existing.id,
                                patient: currentUser,
                                caregivers: RelationshipService.shared.activeRelationships
                            )
                        }
                        closeForm()
                    }
                }
                Button("إلغاء", role: .cancel) {}
            } message: {
                if currentUser.role == .caregiver {
                    Text("هل أنت متأكد من رغبتك في حذف هذا الدواء؟ سيتم حذفه نهائياً من جدول المستفيد وإلغاء جميع التذكيرات.")
                } else if RelationshipService.shared.activeRelationships.isEmpty {
                    Text("هل أنت متأكد من رغبتك في حذف هذا الدواء؟ سيتم إلغاء جميع التذكيرات المرتبطة به.")
                } else {
                    Text("هل أنت متأكد من رغبتك في حذف هذا الدواء؟ سيتم إرسال طلب إلى مقدم الرعاية للموافقة على حذفه نهائياً.")
                }
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
            closeForm()
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

    // MARK: - 2. Screen 1: Main Form Content (Native iOS Inset Grouped)
    private var mainFormContent: some View {
        VStack(spacing: 20) {
            // Section 1: Medication Name & Dosage
            VStack(spacing: 0) {
                HStack {
                    Text("اسم الدواء")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: 90, alignment: .leading)

                    TextField("مثال: ميتروفين", text: $name)
                        .font(.system(size: 17))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)

                Divider().padding(.leading, 16)

                HStack {
                    Text("الجرعة")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: 90, alignment: .leading)

                    TextField("نصف حبة - حبتين، 10 مل", text: $dosage)
                        .font(.system(size: 17))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Section 2: Dose Schedule (opens Dose Time subscreen)
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentSubscreen = .doseTime
                    }
                } label: {
                    HStack {
                        Text("وقت الجرعة")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.primary)

                        Spacer()

                        if hasConfiguredTime {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(timeFormatter.string(from: selectedTime))
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Color.dawaiPrimary)

                                Text("\(selectedFrequencySummary) • \(selectedDays.joined(separator: "، "))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("اضف وقت الجرعة")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: "chevron.forward")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Section 3: Additional Instructions
            VStack(spacing: 0) {
                HStack {
                    Text("تعليمات")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: 90, alignment: .leading)

                    TextField("مثال: بعد الإفطار", text: $instructions)
                        .font(.system(size: 17))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Section 4: Medication Image
            VStack(spacing: 0) {
                if let data = imageData, let uiImage = UIImage(data: data) {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 140)
                            .clipped()

                        Button {
                            withAnimation { self.imageData = nil }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white, Color.black.opacity(0.6))
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button {
                        showingCameraView = true
                    } label: {
                        HStack {
                            Image(systemName: "camera")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.dawaiPrimary)
                            Text("إضافة صورة الدواء")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(Color.dawaiPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Section 5: Delete Medication (in Edit Mode, like Delete Alarm in Apple Clock)
            if mode.isEditing {
                Button {
                    showingDeleteAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Text("حذف الدواء")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Color.red)
                        Spacer()
                    }
                    .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // MARK: - 3. Screen 2: Dose Time Content ("اضف وقت الجرعة" - Pure Apple Clock Alarm Style)
    private var doseTimeContent: some View {
        VStack(spacing: 24) {
            // Apple Clock Bare Wheel Time Picker (Completely native, no card, no glass, no shadow)
            DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 216)
                .frame(maxWidth: .infinity)

            // Apple Clock Inset Grouped Section (Rows underneath)
            VStack(spacing: 0) {
                // Row 1: الايام
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentSubscreen = .days
                    }
                } label: {
                    HStack {
                        Text("الايام")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(selectedDays.joined(separator: "، "))
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Image(systemName: "chevron.forward")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 16)

                // Row 2: التكرار خلال اليوم
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentSubscreen = .frequency
                    }
                } label: {
                    HStack {
                        Text("التكرار خلال اليوم")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(selectedFrequencySummary)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Image(systemName: "chevron.forward")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 16)

                // Row 3: المدة
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentSubscreen = .duration
                    }
                } label: {
                    HStack {
                        Text("المدة")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(selectedDurationSummary)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Image(systemName: "chevron.forward")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
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
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                ForEach(durationOptions.indices, id: \.self) { index in
                    let option = durationOptions[index]
                    selectionOptionRow(
                        title: option,
                        isSelected: selectedDuration == option
                    ) {
                        selectedDuration = option
                    }

                    if index < durationOptions.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Custom "أخرى (مدة مخصصة)"
            VStack(spacing: 0) {
                selectionOptionRow(
                    title: "أخرى (مدة مخصصة)",
                    isSelected: selectedDuration == "اخرى"
                ) {
                    selectedDuration = "اخرى"
                }

                if selectedDuration == "اخرى" {
                    Divider().padding(.leading, 16)

                    HStack(spacing: 12) {
                        Text("المدة")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.secondary)

                        TextField("مثال: 10", text: $customDurationValue)
                            .keyboardType(.numberPad)
                            .font(.system(size: 17))

                        Spacer()

                        Picker("الوحدة", selection: $customDurationUnit) {
                            Text("يوم").tag("يوم")
                            Text("أسبوع").tag("اسبوع")
                            Text("شهر").tag("شهر")
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        VStack(spacing: 0) {
            ForEach(dayOptions.indices, id: \.self) { index in
                let day = dayOptions[index]
                selectionOptionRow(
                    title: day,
                    isSelected: selectedDays.contains(day)
                ) {
                    toggleDay(day)
                }

                if index < dayOptions.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                ForEach(standardFrequencyOptions.indices, id: \.self) { index in
                    let freq = standardFrequencyOptions[index]
                    selectionOptionRow(
                        title: freq,
                        isSelected: selectedFrequency == freq
                    ) {
                        selectedFrequency = freq
                    }

                    if index < standardFrequencyOptions.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // The last option: iOS Dropdown Menu for custom frequency
            VStack(spacing: 0) {
                HStack {
                    Text("حسب أيام محددة\\أوقات محددة")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.primary)

                    Spacer()

                    // Native iOS Dropdown Menu
                    Menu {
                        Section("التكرار اليومي") {
                            Button { selectCustomFrequencyPreset("مرتان يومياً") } label: {
                                HStack { Text("مرتان يومياً"); if customFrequencyText == "مرتان يومياً" { Image(systemName: "checkmark") } }
                            }
                            Button { selectCustomFrequencyPreset("3 مرات يومياً") } label: {
                                HStack { Text("3 مرات يومياً"); if customFrequencyText == "3 مرات يومياً" { Image(systemName: "checkmark") } }
                            }
                            Button { selectCustomFrequencyPreset("4 مرات يومياً") } label: {
                                HStack { Text("4 مرات يومياً"); if customFrequencyText == "4 مرات يومياً" { Image(systemName: "checkmark") } }
                            }
                        }

                        Section("أيام محددة وفترات") {
                            Button { selectCustomFrequencyPreset("كل يومين") } label: {
                                HStack { Text("كل يومين"); if customFrequencyText == "كل يومين" { Image(systemName: "checkmark") } }
                            }
                            Button { selectCustomFrequencyPreset("كل 3 أيام") } label: {
                                HStack { Text("كل 3 أيام"); if customFrequencyText == "كل 3 أيام" { Image(systemName: "checkmark") } }
                            }
                            Button { selectCustomFrequencyPreset("أسبوعياً") } label: {
                                HStack { Text("أسبوعياً"); if customFrequencyText == "أسبوعياً" { Image(systemName: "checkmark") } }
                            }
                            Button { selectCustomFrequencyPreset("شهرياً") } label: {
                                HStack { Text("شهرياً"); if customFrequencyText == "شهرياً" { Image(systemName: "checkmark") } }
                            }
                        }

                        Section("حسب الحاجة والمواعيد") {
                            Button { selectCustomFrequencyPreset("عند اللزوم / الحاجة") } label: {
                                HStack { Text("عند اللزوم / الحاجة"); if customFrequencyText == "عند اللزوم / الحاجة" { Image(systemName: "checkmark") } }
                            }
                            Button { selectCustomFrequencyPreset("قبل النوم") } label: {
                                HStack { Text("قبل النوم"); if customFrequencyText == "قبل النوم" { Image(systemName: "checkmark") } }
                            }
                            Button { selectCustomFrequencyPreset("مع الوجبات") } label: {
                                HStack { Text("مع الوجبات"); if customFrequencyText == "مع الوجبات" { Image(systemName: "checkmark") } }
                            }
                            Button { selectCustomFrequencyPreset("على الريق") } label: {
                                HStack { Text("على الريق"); if customFrequencyText == "على الريق" { Image(systemName: "checkmark") } }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(customFrequencyMenuTitle)
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        }
                    }

                    if isCustomFrequencySelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.dawaiPrimary)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFrequency = "حسب أيام محددة\\أوقات محددة"
                    }
                }

                // Custom Data Entry Field (when selected)
                if isCustomFrequencySelected {
                    Divider().padding(.leading, 16)

                    HStack {
                        TextField("مثال: 3 مرات يومياً، بعد الأكل", text: $customFrequencyText)
                            .font(.system(size: 17))

                        if !customFrequencyText.isEmpty {
                            Button {
                                customFrequencyText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.dawaiPrimary)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Form Submission & Validation (UC-3 S#4 & Alternate Courses)
    private func saveMedication() {
        errorMessage = nil
        isSaving = true

        Task { @MainActor in
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
                closeForm()
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
        formatter.locale = Locale.dawaiArabic
        formatter.dateFormat = "hh:mm a"
        return formatter
    }
}
