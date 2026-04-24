import SwiftUI

// MARK: - Form state

private struct HabitForm {
    var name: String = ""
    var emoji: String = "star.fill"
    var colorHex: String = Habit.palette[0]
    var scheduleType: ScheduleType = .daily
    var customDays: Set<Int> = [1, 2, 3, 4, 5] // Mon-Fri default
    var timesPerWeek: Int = 3
    var targetCount: Int = 1
    var reminderEnabled: Bool = false
    var reminderTime: Date = Calendar.current.date(
        bySettingHour: 8, minute: 0, second: 0, of: Date()
    ) ?? Date()

    enum ScheduleType: String, CaseIterable, Identifiable {
        case daily = "Daily"
        case weekdays = "Weekdays"
        case custom = "Custom"
        case weekly = "N×/week"
        var id: String { rawValue }
    }

    var schedule: HabitSchedule {
        switch scheduleType {
        case .daily:    return .daily
        case .weekdays: return .weekdays
        case .custom:   return .customDays(Array(customDays).sorted())
        case .weekly:   return .timesPerWeek(timesPerWeek)
        }
    }

    init() {}

    init(from habit: Habit) {
        name           = habit.name
        emoji          = habit.emoji
        colorHex       = habit.colorHex
        targetCount    = habit.targetCount
        reminderEnabled = habit.reminderTime != nil
        reminderTime   = habit.reminderTime ?? reminderTime
        switch habit.schedule {
        case .daily:              scheduleType = .daily
        case .weekdays:           scheduleType = .weekdays
        case .customDays(let d):  scheduleType = .custom;  customDays = Set(d)
        case .timesPerWeek(let n):scheduleType = .weekly;  timesPerWeek = n
        }
    }

    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
}

// MARK: - SF Symbol picker options

private let habitSymbols: [String] = [
    // Running & Walking
    "figure.run", "figure.walk", "figure.hiking",
    "figure.outdoor.cycle", "bicycle", "figure.indoor.cycle",
    // Strength & Conditioning
    "figure.strengthtraining.traditional", "figure.core.training",
    "figure.highintensity.intervaltraining", "figure.flexibility",
    "figure.cooldown", "dumbbell.fill",
    // Mind & Body
    "figure.yoga", "figure.pilates", "figure.mind.and.body",
    "figure.martial.arts", "figure.dance",
    // Sports
    "figure.open.water.swim", "figure.soccer",
    "figure.basketball", "figure.tennis",
    "figure.boxing", "figure.golf",
    "figure.skiing.downhill",
    // Health
    "heart.fill", "cross.fill", "waveform.path.ecg",
    "drop.fill", "pills.fill", "stethoscope",
    "lungs.fill", "brain.head.profile", "bandage.fill",
    "eye.fill", "bed.double.fill",
    // Food & Drink
    "fork.knife", "cup.and.saucer.fill", "mug.fill",
    "apple.logo",
    // Mindfulness & Nature
    "moon.fill", "sparkles", "leaf.fill",
    "sun.max.fill", "cloud.fill", "wind", "snowflake",
    // Learning & Creativity
    "book.fill", "pencil", "paintbrush.fill",
    "music.note", "headphones", "mic.fill",
    "newspaper.fill", "theatermasks.fill", "photo.fill",
    // Productivity & Goals
    "star.fill", "checkmark.circle.fill", "target",
    "flag.fill", "chart.bar.fill", "clock.fill",
    "alarm.fill", "timer", "bolt.fill",
    "calendar.badge.checkmark", "note.text", "flame.fill",
    // Lifestyle & Social
    "person.2.fill", "globe", "camera.fill",
    "trophy.fill", "lightbulb.fill", "house.fill",
    "car.fill", "airplane", "bag.fill",
    "dollarsign.circle.fill", "phone.fill",
    "laptopcomputer", "wrench.and.screwdriver.fill",
]

// MARK: - View

struct AddEditHabitView: View {

    let existingHabit: Habit?
    let onSave: (Habit) -> Void
    let onCancel: () -> Void

    @State private var form: HabitForm
    @State private var showSymbolPicker = false

    init(existingHabit: Habit? = nil,
         onSave: @escaping (Habit) -> Void,
         onCancel: @escaping () -> Void) {
        self.existingHabit = existingHabit
        self.onSave = onSave
        self.onCancel = onCancel
        _form = State(initialValue: existingHabit.map { HabitForm(from: $0) } ?? HabitForm())
    }

    private var accentColor: Color { Color(hex: form.colorHex) }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                colorSection
                scheduleSection
                if form.targetCount > 0 {
                    targetSection
                }
                reminderSection
            }
            .navigationTitle(existingHabit == nil ? "New Habit" : "Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { commitSave() }
                        .fontWeight(.semibold)
                        .disabled(!form.isValid)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Identity

    private var identitySection: some View {
        Section {
            HStack(spacing: 14) {
                Button {
                    withAnimation(.spring(response: 0.3)) { showSymbolPicker.toggle() }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(accentColor.opacity(0.12))
                            .frame(width: 54, height: 54)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(accentColor.opacity(showSymbolPicker ? 0.7 : 0), lineWidth: 2)
                            )
                        HabitSymbolView(form.emoji, color: accentColor, size: .title2)
                    }
                }
                .buttonStyle(.plain)

                TextField("Habit name", text: $form.name)
                    .font(.headline)
                    .submitLabel(.done)
            }
            .padding(.vertical, 4)

            if showSymbolPicker {
                symbolGrid
            }
        } header: {
            Text("Identity")
        }
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: Array(repeating: .init(.flexible(minimum: 36, maximum: 44)), count: 8),
                  spacing: 10) {
            ForEach(habitSymbols, id: \.self) { sym in
                Button {
                    form.emoji = sym
                    showSymbolPicker = false
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(form.emoji == sym
                                  ? accentColor.opacity(0.20)
                                  : Color(UIColor.systemGray6))
                            .frame(width: 40, height: 40)
                        Image(systemName: sym)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(form.emoji == sym ? accentColor : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Color

    private var colorSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Habit.palette, id: \.self) { hex in
                        let selected = form.colorHex == hex
                        Button {
                            form.colorHex = hex
                        } label: {
                            ZStack {
                                Circle().fill(Color(hex: hex))
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 36, height: 36)
                            .shadow(color: selected ? Color(hex: hex).opacity(0.5) : .clear, radius: 4)
                            .scaleEffect(selected ? 1.12 : 1.0)
                            .animation(.spring(response: 0.25), value: selected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Color \(hex)\(selected ? ", selected" : "")")
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
        } header: {
            Text("Color")
        }
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        Section {
            Picker("Frequency", selection: $form.scheduleType) {
                ForEach(HabitForm.ScheduleType.allCases) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            if form.scheduleType == .custom {
                customDaysPicker
            }
            if form.scheduleType == .weekly {
                Stepper(
                    "Times per week: \(form.timesPerWeek)",
                    value: $form.timesPerWeek, in: 1...7
                )
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text(scheduleFooter).foregroundStyle(.secondary)
        }
    }

    private var customDaysPicker: some View {
        let labels = ["S", "M", "T", "W", "T", "F", "S"]
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let selected = form.customDays.contains(i)
                Button {
                    if selected { form.customDays.remove(i) }
                    else { form.customDays.insert(i) }
                } label: {
                    Text(labels[i])
                        .font(.callout.weight(selected ? .bold : .regular))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(selected ? .white : accentColor)
                        .background(
                            Circle().fill(selected ? accentColor : accentColor.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.25), value: selected)
            }
        }
        .padding(.vertical, 4)
    }

    private var scheduleFooter: String {
        switch form.scheduleType {
        case .daily:    return "Habit is due every day."
        case .weekdays: return "Habit is due Monday–Friday."
        case .custom:
            if form.customDays.isEmpty { return "Select at least one day." }
            return "Habit is due on the selected days."
        case .weekly:   return "Habit is due \(form.timesPerWeek)× per week, any day."
        }
    }

    // MARK: - Target

    private var targetSection: some View {
        Section {
            Stepper("Daily target: \(form.targetCount)", value: $form.targetCount, in: 1...99)
        } header: {
            Text("Daily Target")
        } footer: {
            Text(form.targetCount == 1
                 ? "Binary completion — one tap marks it done."
                 : "Track up to \(form.targetCount) completions per day (e.g. glasses of water).")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Reminder

    private var reminderSection: some View {
        Section {
            Toggle("Enable reminder", isOn: $form.reminderEnabled)
                .tint(accentColor)
            if form.reminderEnabled {
                DatePicker(
                    "Reminder time",
                    selection: $form.reminderTime,
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text("Reminder")
        } footer: {
            if form.reminderEnabled {
                Text("Notifications require permission in iOS Settings.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Save

    private func commitSave() {
        let trimmedName = form.name.trimmingCharacters(in: .whitespaces)
        if let existing = existingHabit {
            existing.name         = trimmedName
            existing.emoji        = form.emoji
            existing.colorHex     = form.colorHex
            existing.schedule     = form.schedule
            existing.targetCount  = form.targetCount
            existing.reminderTime = form.reminderEnabled ? form.reminderTime : nil
            onSave(existing)
        } else {
            onSave(Habit(
                name:         trimmedName,
                emoji:        form.emoji,
                colorHex:     form.colorHex,
                schedule:     form.schedule,
                targetCount:  form.targetCount,
                reminderTime: form.reminderEnabled ? form.reminderTime : nil
            ))
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Add habit") {
    AddEditHabitView(onSave: { _ in }, onCancel: {})
}

#Preview("Edit habit") {
    let h = Habit(name: "Morning Run", emoji: "🏃", colorHex: "34C759",
                  schedule: .weekdays, targetCount: 1)
    return AddEditHabitView(existingHabit: h, onSave: { _ in }, onCancel: {})
}
#endif
