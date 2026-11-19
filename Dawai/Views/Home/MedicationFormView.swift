//
//  MedicationFormView.swift
//  Dawai
//
//  Created by Dawai Team.
//  Medication Add/Edit Form - Simplified native iOS design (all in one screen).
//

import SwiftUI
import UIKit

public enum MedicationFormMode: Equatable {
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

public struct MedicationFormView: View {
    public let mode: MedicationFormMode
    public let currentUser: UserIdentity
    public var targetPatient: BeneficiarySummary?
    public var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var medicationService = MedicationService.shared
    @ObservedObject private var themeService = ThemeService.shared

    // Form Inputs
    @State private var name: String = ""
    @State private var strength: String = ""
    @State private var doseTimes: [Date] = [MedicationFormView.defaultInitialDoseTime()]
    @State private var expandedDoseIndex: Int? = nil

    // Frequency & Duration Sheets
    @State private var showingFrequencySheet: Bool = false
    @State private var showingDurationSheet: Bool = false

    // Frequency state: .daily, .everyOtherDay, .specificWeekdays
    @State private var frequencyType: MedicationScheduleType = .daily
    @State private var selectedWeekdays: Set<Int> = []

    // Duration state: continuous vs forDays(1...90)
    @State private var isContinuousDuration: Bool = true
    @State private var durationDaysCount: Int = 7

    // Additional Fields
    @State private var instructions: String = ""
    @State private var imageData: Data? = nil

    // UI & Validation State
    @State private var errorMessage: String? = nil
    @State private var showingCameraView: Bool = false
    @State private var showingDeleteAlert: Bool = false
    @State private var isSaving: Bool = false
    @State private var didInitializeForm: Bool = false

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
                    if let err = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .dawaiFont(size: 14)
                            Text(err)
                                .dawaiFont(size: 13, weight: .semibold)
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color.red.opacity(0.85))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    ScrollView {
                        VStack(spacing: 20) {
                            // أ) مجموعة: "اسم الدواء" و"القوة"
                            nameAndStrengthSection

                            // ب) قسم بعنوان "الأوقات": قائمة الجرعات + زر "+ إضافة وقت"
                            timesSection

                            // ج) مجموعة فيها صفّين: "التكرار" و"المدة"
                            frequencyAndDurationSection

                            // د) حقل "تعليمات"
                            instructionsSection

                            // هـ) صف "إضافة صورة الدواء"
                            imageSection

                            // و) صندوق ملخص بخلفية خضراء فاتحة ونص أخضر
                            summaryBoxSection

                            // حذف الدواء (في وضع التعديل)
                            if mode.isEditing {
                                deleteButtonSection
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 36)
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("إلغاء") {
                        closeForm()
                    }
                    .foregroundStyle(Color.dawaiPrimary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("حفظ") {
                        saveMedication()
                    }
                    .dawaiFont(size: 17, weight: .semibold)
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
            .sheet(isPresented: $showingFrequencySheet) {
                frequencySheetView
            }
            .sheet(isPresented: $showingDurationSheet) {
                durationSheetView
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
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale.dawaiArabic)
    }

    // MARK: - Initializer for Edit Mode
    private func initializeFormValues() {
        guard !didInitializeForm else { return }
        didInitializeForm = true

        if case .edit(let item) = mode {
            self.name = item.name
            self.strength = item.dosage
            self.instructions = item.instructions ?? ""
            self.imageData = item.imageData

            // Times
            let minutesList = !item.customDoseTimesMinutes.isEmpty
                ? item.customDoseTimesMinutes
                : medicationService.dailyDoseTimesMinutes(for: item)

            if !minutesList.isEmpty {
                self.doseTimes = Array(minutesList.prefix(6)).map { dateFromMinutes($0) }
            } else {
                let firstMin = medicationService.scheduledMinutes(for: item)
                self.doseTimes = [dateFromMinutes(firstMin)]
            }

            // Frequency
            if item.scheduleType == .everyOtherDay || item.frequency.contains("يوم بعد يوم") || item.days.contains("يوم بعد يوم") {
                self.frequencyType = .everyOtherDay
                self.selectedWeekdays = []
            } else if !item.selectedWeekdays.isEmpty || item.scheduleType == .specificWeekdays {
                self.frequencyType = .specificWeekdays
                self.selectedWeekdays = item.selectedWeekdays
            } else {
                self.frequencyType = .daily
                self.selectedWeekdays = []
            }

            // Duration
            if item.duration.isEmpty || item.duration == "دائم" || item.duration == "مستمر" || item.endDate == nil {
                self.isContinuousDuration = true
                self.durationDaysCount = 7
            } else {
                self.isContinuousDuration = false
                let days = parseDaysCount(from: item.duration) ?? 7
                self.durationDaysCount = max(1, min(90, days))
            }
        }
    }

    // MARK: - 1. Name & Strength Section
    private var nameAndStrengthSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("اسم الدواء")
                    .dawaiFont(size: 17, weight: .regular)
                    .foregroundStyle(.primary)
                    .frame(width: 90, alignment: .leading)

                TextField("مثال: فيفادول", text: $name)
                    .dawaiFont(size: 17)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)

            Divider().padding(.leading, 16)

            HStack {
                Text("القوة")
                    .dawaiFont(size: 17, weight: .regular)
                    .foregroundStyle(.primary)
                    .frame(width: 90, alignment: .leading)

                TextField("مثال: 500 ملغ، حبة واحدة", text: $strength)
                    .dawaiFont(size: 17)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 2. Times Section (Dose List + Add Time Button)
    private var timesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("الأوقات")
                .dawaiFont(size: 14, weight: .regular)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(doseTimes.indices, id: \.self) { index in
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            // Dose Title (الجرعة / الأولى / الثانية...)
                            Text(doseTitle(for: index, count: doseTimes.count))
                                .dawaiFont(size: 17, weight: .regular)
                                .foregroundStyle(.primary)

                            Spacer()

                            // Time capsule button (opens/closes inline wheel)
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    if expandedDoseIndex == index {
                                        expandedDoseIndex = nil
                                    } else {
                                        expandedDoseIndex = index
                                    }
                                }
                            } label: {
                                Text(formatDoseTime(doseTimes[index]))
                                    .dawaiFont(size: 17, weight: .semibold)
                                    .foregroundStyle(Color.dawaiPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        Color(uiColor: .tertiarySystemFill),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)

                            // Delete button (X) when more than 1 dose time
                            if doseTimes.count > 1 {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        deleteTime(at: index)
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .dawaiFont(size: 14, weight: .bold)
                                        .foregroundStyle(Color.red)
                                        .frame(width: 24, height: 24)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)

                        // Inline DatePicker Wheel when capsule is tapped
                        if expandedDoseIndex == index {
                            Divider().padding(.horizontal, 16)

                            DatePicker(
                                "",
                                selection: $doseTimes[index],
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .environment(\.layoutDirection, .leftToRight)
                            .environment(\.locale, Locale.dawaiArabic)
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    if index < doseTimes.count - 1 || doseTimes.count < 6 {
                        Divider().padding(.leading, 16)
                    }
                }

                // Add Time Button: up to 6 times
                if doseTimes.count < 6 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            addNewTime()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("+ إضافة وقت")
                                .dawaiFont(size: 17, weight: .semibold)
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
        }
    }

    private func doseTitle(for index: Int, count: Int) -> String {
        if count == 1 {
            return "الجرعة"
        }
        switch index {
        case 0: return "الجرعة الأولى"
        case 1: return "الجرعة الثانية"
        case 2: return "الجرعة الثالثة"
        case 3: return "الجرعة الرابعة"
        case 4: return "الجرعة الخامسة"
        case 5: return "الجرعة السادسة"
        default: return "الجرعة \(index + 1)"
        }
    }

    private func addNewTime() {
        guard doseTimes.count < 6 else { return }
        let lastTime = doseTimes.last ?? MedicationFormView.defaultInitialDoseTime()
        // Add 6 hours
        let newTime = Calendar.current.date(byAdding: .hour, value: 6, to: lastTime) ?? lastTime
        doseTimes.append(newTime)
        expandedDoseIndex = doseTimes.count - 1
    }

    private func deleteTime(at index: Int) {
        guard doseTimes.count > 1, index < doseTimes.count else { return }
        doseTimes.remove(at: index)
        if expandedDoseIndex == index {
            expandedDoseIndex = nil
        } else if let expanded = expandedDoseIndex, expanded > index {
            expandedDoseIndex = expanded - 1
        }
    }

    // MARK: - 3. Frequency & Duration Section
    private var frequencyAndDurationSection: some View {
        VStack(spacing: 0) {
            // Row: التكرار
            Button {
                showingFrequencySheet = true
            } label: {
                HStack {
                    Text("التكرار")
                        .dawaiFont(size: 17, weight: .regular)
                        .foregroundStyle(.primary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "chevron.down")
                            .dawaiFont(size: 13, weight: .semibold)
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))

                        Text(frequencyRowSummary)
                            .dawaiFont(size: 17, weight: .regular)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 16)

            // Row: المدة
            Button {
                showingDurationSheet = true
            } label: {
                HStack {
                    Text("المدة")
                        .dawaiFont(size: 17, weight: .regular)
                        .foregroundStyle(.primary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "chevron.down")
                            .dawaiFont(size: 13, weight: .semibold)
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))

                        Text(durationRowSummary)
                            .dawaiFont(size: 17, weight: .regular)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
            }
            .buttonStyle(.plain)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 4. Instructions Section
    private var instructionsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("تعليمات")
                    .dawaiFont(size: 17, weight: .regular)
                    .foregroundStyle(.primary)
                    .frame(width: 90, alignment: .leading)

                TextField("مثال: بعد الأكل، مع كوب ماء", text: $instructions)
                    .dawaiFont(size: 17)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 5. Image Section
    private var imageSection: some View {
        VStack(spacing: 0) {
            if let data = imageData, let uiImage = UIImage(data: data) {
                VStack(spacing: 0) {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .clipped()

                        Button {
                            withAnimation { self.imageData = nil }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .dawaiFont(size: 24)
                                .foregroundStyle(.white, Color.black.opacity(0.65))
                                .padding(10)
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()

                    Button {
                        showingCameraView = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.rotate")
                                .dawaiFont(size: 15, weight: .semibold)
                            Text("تغيير صورة الدواء")
                                .dawaiFont(size: 15, weight: .semibold)
                            Spacer()
                            Image(systemName: "chevron.left")
                                .dawaiFont(size: 14, weight: .semibold)
                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        }
                        .foregroundStyle(Color.dawaiPrimary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    showingCameraView = true
                } label: {
                    HStack(spacing: 8) {
                        Spacer()

                        Image(systemName: "camera")
                            .dawaiFont(size: 18)

                        Text("إضافة صورة الدواء")
                            .dawaiFont(size: 17, weight: .regular)

                        Spacer()
                    }
                    .foregroundStyle(Color.dawaiPrimary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 6. Summary Box Section
    private var summaryBoxSection: some View {
        HStack {
            Spacer()
            Text(summaryText)
                .dawaiFont(size: 16, weight: .semibold)
                .foregroundStyle(Color(red: 0.08, green: 0.65, blue: 0.62))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            Color(red: 0.08, green: 0.65, blue: 0.62).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var summaryText: String {
        let medName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "الدواء" : name
        let countText = timesCountArabic(doseTimes.count)
        let formattedTimes = doseTimes.map { formatDoseTime($0) }.joined(separator: "، ")
        let freqText = frequencyRowSummary
        let durText = durationRowSummary
        return "\(medName): \(countText) (\(formattedTimes))، \(freqText)، \(durText)."
    }

    private func timesCountArabic(_ count: Int) -> String {
        switch count {
        case 1: return "مرة يومياً"
        case 2: return "مرتين يومياً"
        case 3: return "3 مرات يومياً"
        case 4: return "4 مرات يومياً"
        case 5: return "5 مرات يومياً"
        case 6: return "6 مرات يومياً"
        default: return "\(count) مرات يومياً"
        }
    }

    // MARK: - 7. Delete Button Section
    private var deleteButtonSection: some View {
        Button {
            showingDeleteAlert = true
        } label: {
            HStack {
                Spacer()
                Text("حذف الدواء")
                    .dawaiFont(size: 17, weight: .regular)
                    .foregroundStyle(Color.red)
                Spacer()
            }
            .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Frequency Sheet («أي أيام تاخذه؟»)
    private let weekdayItems: [(id: Int, title: String)] = [
        (1, "الأحد"),
        (2, "الاثنين"),
        (3, "الثلاثاء"),
        (4, "الأربعاء"),
        (5, "الخميس"),
        (6, "الجمعة"),
        (7, "السبت")
    ]

    private var frequencySheetView: some View {
        NavigationStack {
            List {
                Section {
                    // Option 1: كل يوم
                    Button {
                        frequencyType = .daily
                        selectedWeekdays.removeAll()
                    } label: {
                        HStack {
                            Text("كل يوم")
                                .dawaiFont(size: 17)
                                .foregroundStyle(.primary)

                            Spacer()

                            if frequencyType == .daily {
                                Image(systemName: "checkmark")
                                    .dawaiFont(size: 15, weight: .semibold)
                                    .foregroundStyle(Color.dawaiPrimary)
                            }
                        }
                    }

                    // Option 2: يوم بعد يوم
                    Button {
                        frequencyType = .everyOtherDay
                        selectedWeekdays.removeAll()
                    } label: {
                        HStack {
                            Text("يوم بعد يوم")
                                .dawaiFont(size: 17)
                                .foregroundStyle(.primary)

                            Spacer()

                            if frequencyType == .everyOtherDay {
                                Image(systemName: "checkmark")
                                    .dawaiFont(size: 15, weight: .semibold)
                                    .foregroundStyle(Color.dawaiPrimary)
                            }
                        }
                    }

                    // Option 3: أيام محددة
                    Button {
                        frequencyType = .specificWeekdays
                    } label: {
                        HStack {
                            Text("أيام محددة")
                                .dawaiFont(size: 17)
                                .foregroundStyle(.primary)

                            Spacer()

                            if frequencyType == .specificWeekdays {
                                Image(systemName: "checkmark")
                                    .dawaiFont(size: 15, weight: .semibold)
                                    .foregroundStyle(Color.dawaiPrimary)
                            }
                        }
                    }
                }

                // If "أيام محددة" selected, show the weekdays list
                if frequencyType == .specificWeekdays {
                    Section {
                        ForEach(weekdayItems, id: \.id) { item in
                            Button {
                                toggleWeekday(item.id)
                            } label: {
                                HStack {
                                    Text(item.title)
                                        .dawaiFont(size: 17)
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    if selectedWeekdays.contains(item.id) {
                                        Image(systemName: "checkmark")
                                            .dawaiFont(size: 15, weight: .semibold)
                                            .foregroundStyle(Color.dawaiPrimary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("أي أيام تاخذه؟")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("تم") {
                        if frequencyType == .specificWeekdays && selectedWeekdays.isEmpty {
                            errorMessage = "اختر يوم واحد على الأقل"
                        }
                        showingFrequencySheet = false
                    }
                    .dawaiFont(size: 17, weight: .semibold)
                    .foregroundStyle(Color.dawaiPrimary)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale.dawaiArabic)
        }
        .presentationDetents([.medium, .large])
    }

    private func toggleWeekday(_ id: Int) {
        if selectedWeekdays.contains(id) {
            selectedWeekdays.remove(id)
        } else {
            selectedWeekdays.insert(id)
        }
    }

    private var frequencyRowSummary: String {
        switch frequencyType {
        case .daily:
            return "كل يوم"
        case .everyOtherDay:
            return "يوم بعد يوم"
        case .specificWeekdays:
            let names = weekdayItems
                .filter { selectedWeekdays.contains($0.id) }
                .map { $0.title }
            return names.isEmpty ? "اختر الأيام" : names.joined(separator: "، ")
        case .asNeeded:
            return "كل يوم"
        }
    }

    // MARK: - Duration Sheet («إلى متى تاخذه؟»)
    private var durationSheetView: some View {
        NavigationStack {
            List {
                Section {
                    // Option 1: مستمر
                    Button {
                        isContinuousDuration = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("مستمر")
                                    .dawaiFont(size: 17)
                                    .foregroundStyle(.primary)

                                Text("بدون تاريخ نهاية")
                                    .dawaiFont(size: 13)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if isContinuousDuration {
                                Image(systemName: "checkmark")
                                    .dawaiFont(size: 15, weight: .semibold)
                                    .foregroundStyle(Color.dawaiPrimary)
                            }
                        }
                    }

                    // Option 2: لعدد أيام
                    Button {
                        isContinuousDuration = false
                    } label: {
                        HStack {
                            Text("لعدد أيام")
                                .dawaiFont(size: 17)
                                .foregroundStyle(.primary)

                            Spacer()

                            if !isContinuousDuration {
                                Image(systemName: "checkmark")
                                    .dawaiFont(size: 15, weight: .semibold)
                                    .foregroundStyle(Color.dawaiPrimary)
                            }
                        }
                    }
                }

                // If "لعدد أيام" selected, show the native picker from 1 to 90
                if !isContinuousDuration {
                    Section {
                        HStack {
                            Picker("عدد الأيام", selection: $durationDaysCount) {
                                ForEach(1...90, id: \.self) { day in
                                    Text(formattedDaysCount(day)).tag(day)
                                }
                            }
                            .pickerStyle(.menu)
                            .dawaiFont(size: 17)

                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("إلى متى تاخذه؟")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("تم") {
                        showingDurationSheet = false
                    }
                    .dawaiFont(size: 17, weight: .semibold)
                    .foregroundStyle(Color.dawaiPrimary)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale.dawaiArabic)
        }
        .presentationDetents([.medium, .large])
    }

    private func formattedDaysCount(_ n: Int) -> String {
        switch n {
        case 1: return "يوم"
        case 2: return "يومين"
        case 3...10: return "\(n) أيام"
        default: return "\(n) يوم"
        }
    }

    private var durationRowSummary: String {
        if isContinuousDuration {
            return "مستمر"
        }
        return formattedDaysCount(durationDaysCount)
    }

    // MARK: - Save Medication
    private func saveMedication() {
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            withAnimation {
                errorMessage = "اكتب اسم الدواء"
            }
            return
        }

        if frequencyType == .specificWeekdays && selectedWeekdays.isEmpty {
            withAnimation {
                errorMessage = "اختر يوم واحد على الأقل"
            }
            return
        }

        isSaving = true

        Task { @MainActor in
            do {
                let chosenMinutes = doseTimes.map { minutesFromDate($0) }.sorted()
                let firstTimeStr = chosenMinutes.first.map { medicationService.formattedTimeString(forSlotMinutes: $0) }
                    ?? (doseTimes.first.map { formatDoseTime($0) } ?? "08:00 ص")

                let durationFinal = durationRowSummary
                let freqFinal = timesCountArabic(doseTimes.count)

                let daysFinal: [String]
                switch frequencyType {
                case .daily:
                    daysFinal = ["كل يوم"]
                case .everyOtherDay:
                    daysFinal = ["يوم بعد يوم"]
                case .specificWeekdays:
                    let names = weekdayItems.filter { selectedWeekdays.contains($0.id) }.map { $0.title }
                    daysFinal = names.isEmpty ? ["كل يوم"] : names
                case .asNeeded:
                    daysFinal = ["كل يوم"]
                }

                let finalEndDate: Date?
                if isContinuousDuration {
                    finalEndDate = nil
                } else {
                    let cal = Calendar.current
                    let startDay = cal.startOfDay(for: Date())
                    if let endDay = cal.date(byAdding: .day, value: durationDaysCount - 1, to: startDay) {
                        var comps = cal.dateComponents([.year, .month, .day], from: endDay)
                        comps.hour = 23
                        comps.minute = 59
                        comps.second = 59
                        finalEndDate = cal.date(from: comps)
                    } else {
                        finalEndDate = nil
                    }
                }

                let structuredWeekdays: Set<Int> = (frequencyType == .specificWeekdays) ? selectedWeekdays : []

                switch mode {
                case .add:
                    let newMedication = MedicationItem(
                        patientId: currentUser.role == .caregiver ? (targetPatient?.patientId ?? "") : currentUser.id,
                        name: trimmedName,
                        dosage: strength.isEmpty ? "حبة واحدة" : strength,
                        timeString: firstTimeStr,
                        scheduledDate: doseTimes.first,
                        days: daysFinal,
                        selectedWeekdays: structuredWeekdays,
                        frequency: freqFinal,
                        duration: durationFinal,
                        instructions: instructions.isEmpty ? nil : instructions,
                        imageData: imageData,
                        isTaken: false,
                        scheduleType: frequencyType,
                        customDoseTimesMinutes: chosenMinutes,
                        startDate: Date(),
                        endDate: finalEndDate
                    )

                    try await medicationService.addMedication(
                        item: newMedication,
                        currentUser: currentUser,
                        targetPatientId: targetPatient?.patientId
                    )

                case .edit(let existing):
                    var updated = existing
                    updated.name = trimmedName
                    updated.dosage = strength.isEmpty ? "حبة واحدة" : strength
                    updated.timeString = firstTimeStr
                    updated.scheduledDate = doseTimes.first
                    updated.days = daysFinal
                    updated.selectedWeekdays = structuredWeekdays
                    updated.frequency = freqFinal
                    updated.duration = durationFinal
                    updated.instructions = instructions.isEmpty ? nil : instructions
                    updated.imageData = imageData
                    updated.scheduleType = frequencyType
                    updated.customDoseTimesMinutes = chosenMinutes
                    updated.startDate = existing.startDate
                    updated.endDate = finalEndDate

                    try await medicationService.updateMedication(
                        item: updated,
                        currentUser: currentUser,
                        targetPatientId: targetPatient?.patientId
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

    // MARK: - Date Helpers
    private func formatDoseTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let totalMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        return medicationService.formattedTimeString(forSlotMinutes: totalMinutes)
    }

    private func minutesFromDate(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func dateFromMinutes(_ mins: Int) -> Date {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.hour = mins / 60
        comps.minute = mins % 60
        comps.second = 0
        return calendar.date(from: comps) ?? Date()
    }

    private static func defaultInitialDoseTime() -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 8
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func parseDaysCount(from durationStr: String) -> Int? {
        let clean = durationStr.westernNumerals
        let digits = clean.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        if let count = Int(digits), count > 0 {
            return count
        }
        if durationStr.contains("يومين") { return 2 }
        if durationStr.contains("أسبوع") || durationStr.contains("اسبوع") { return 7 }
        if durationStr.contains("أسبوعين") || durationStr.contains("اسبوعين") { return 14 }
        if durationStr.contains("شهر") { return 30 }
        return nil
    }
}
