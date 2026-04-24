import SwiftUI

// MARK: - Form state

private struct MedForm {
    var name: String = ""
    var emoji: String = "pill.fill"
    var colorHex: String = Habit.palette[1]
    var strength: String = ""
    var form: MedicationForm = .tablet
    var prescriber: String = ""
    var scheduleType: ScheduleType = .daily
    var customDays: Set<Int> = [1, 2, 3, 4, 5]
    var doseTimes: [Date] = [Self.makeTime(hour: 8)]
    var startDate: Date = Calendar.current.startOfDay(for: Date())
    var hasEndDate: Bool = false
    var endDate: Date = Calendar.current.startOfDay(for: Date())
    var notes: String = ""

    // Inventory
    var trackInventory: Bool = false
    var pillCount: Int = 30
    var pillsPerDose: Int = 1
    var lowStockThreshold: Int = 7

    enum ScheduleType: String, CaseIterable, Identifiable {
        case daily    = "Daily"
        case weekdays = "Weekdays"
        case custom   = "Custom"
        case asNeeded = "As Needed"
        var id: String { rawValue }
    }

    static func makeTime(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    var schedule: MedicationSchedule {
        switch scheduleType {
        case .daily:    return .daily
        case .weekdays: return .weekdays
        case .custom:   return .customDays(Array(customDays).sorted())
        case .asNeeded: return .asNeeded
        }
    }

    var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return scheduleType == .asNeeded || !doseTimes.isEmpty
    }

    init() {}

    init(from med: Medication) {
        name              = med.name
        emoji             = med.emoji
        colorHex          = med.colorHex
        strength          = med.strength
        form              = med.form
        prescriber        = med.prescriber ?? ""
        doseTimes         = med.dosesPerDay.isEmpty ? [Self.makeTime(hour: 8)] : med.dosesPerDay
        startDate         = med.startDate
        hasEndDate        = med.endDate != nil
        endDate           = med.endDate ?? Calendar.current.startOfDay(for: Date())
        notes             = med.notes ?? ""
        trackInventory    = med.pillCount != nil
        pillCount         = med.pillCount ?? 30
        pillsPerDose      = med.pillsPerDose
        lowStockThreshold = med.lowStockThreshold
        switch med.schedule {
        case .daily:              scheduleType = .daily
        case .weekdays:           scheduleType = .weekdays
        case .customDays(let d):  scheduleType = .custom;   customDays = Set(d)
        case .asNeeded:           scheduleType = .asNeeded
        }
    }
}

// MARK: - View

struct AddEditMedicationView: View {

    let existing: Medication?
    let onSave: (Medication) -> Void
    let onCancel: () -> Void

    @State private var form: MedForm
    @State private var showSymbolPicker = false

    init(existing: Medication? = nil,
         onSave: @escaping (Medication) -> Void,
         onCancel: @escaping () -> Void) {
        self.existing = existing
        self.onSave   = onSave
        self.onCancel = onCancel
        _form = State(initialValue: existing.map { MedForm(from: $0) } ?? MedForm())
    }

    private var accentColor: Color { Color(hex: form.colorHex) }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                colorSection
                scheduleSection
                if form.scheduleType != .asNeeded {
                    doseTimesSection
                }
                datesSection
                inventorySection
                detailsSection
            }
            .navigationTitle(existing == nil ? "New Medication" : "Edit Medication")
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
                        Image(systemName: form.emoji)
                            .font(.title2)
                            .foregroundStyle(accentColor)
                    }
                }
                .buttonStyle(.plain)

                TextField("Medication name", text: $form.name)
                    .font(.headline)
                    .submitLabel(.done)
            }
            .padding(.vertical, 4)

            if showSymbolPicker { symbolGrid }
        } header: { Text("Identity") }
    }

    private var symbolGrid: some View {
        LazyVGrid(
            columns: Array(repeating: .init(.flexible(minimum: 36, maximum: 44)), count: 8),
            spacing: 10
        ) {
            ForEach(medSymbols, id: \.self) { sym in
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
                        Button { form.colorHex = hex } label: {
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
        } header: { Text("Color") }
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        Section {
            Picker("Frequency", selection: $form.scheduleType) {
                ForEach(MedForm.ScheduleType.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            if form.scheduleType == .custom { customDaysPicker }
        } header: { Text("Schedule") }
    }

    private var customDaysPicker: some View {
        let labels = ["S", "M", "T", "W", "T", "F", "S"]
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let selected = form.customDays.contains(i)
                Button {
                    if selected { form.customDays.remove(i) }
                    else        { form.customDays.insert(i) }
                } label: {
                    Text(labels[i])
                        .font(.callout.weight(selected ? .bold : .regular))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(selected ? .white : accentColor)
                        .background(Circle().fill(selected ? accentColor : accentColor.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.25), value: selected)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Dose times

    private var doseTimesSection: some View {
        Section {
            ForEach(form.doseTimes.indices, id: \.self) { i in
                HStack {
                    DatePicker(
                        "Dose \(i + 1)",
                        selection: $form.doseTimes[i],
                        displayedComponents: .hourAndMinute
                    )
                    if form.doseTimes.count > 1 {
                        Button {
                            form.doseTimes.remove(at: i)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                let lastHour = Calendar.current.component(.hour, from: form.doseTimes.last ?? Date())
                form.doseTimes.append(MedForm.makeTime(hour: min(23, lastHour + 8)))
            } label: {
                Label("Add dose time", systemImage: "plus.circle.fill")
            }
        } header: { Text("Dose Times") } footer: {
            Text("A reminder notification is sent at each time on scheduled days.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Dates

    private var datesSection: some View {
        Section {
            DatePicker("Start date", selection: $form.startDate, displayedComponents: .date)
            Toggle("Has end date", isOn: $form.hasEndDate)
                .tint(accentColor)
            if form.hasEndDate {
                DatePicker("End date", selection: $form.endDate, in: form.startDate..., displayedComponents: .date)
            }
        } header: { Text("Duration") }
    }

    // MARK: - Inventory

    private var inventorySection: some View {
        Section {
            Toggle("Track pill count", isOn: $form.trackInventory)
                .tint(accentColor)
            if form.trackInventory {
                Stepper("Current supply: \(form.pillCount)", value: $form.pillCount, in: 0...9999)
                Stepper("Pills per dose: \(form.pillsPerDose)", value: $form.pillsPerDose, in: 1...20)
                Stepper("Low-stock alert at: \(form.lowStockThreshold)", value: $form.lowStockThreshold, in: 0...100)
            }
        } header: { Text("Inventory") } footer: {
            if form.trackInventory {
                Text("You'll be notified when supply drops to \(form.lowStockThreshold) or fewer.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        Section {
            HStack {
                Text("Strength")
                Spacer()
                TextField("e.g. 500 mg", text: $form.strength)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            }
            Picker("Form", selection: $form.form) {
                ForEach(MedicationForm.allCases) { f in
                    Label(f.displayName, systemImage: f.sfSymbol).tag(f)
                }
            }
            HStack {
                Text("Prescriber")
                Spacer()
                TextField("Optional", text: $form.prescriber)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            }
            TextField("Notes", text: $form.notes, axis: .vertical)
                .lineLimit(2...6)
        } header: { Text("Details") }
    }

    // MARK: - Save

    private func commitSave() {
        let trimmed = form.name.trimmingCharacters(in: .whitespaces)
        if let med = existing {
            med.name              = trimmed
            med.emoji             = form.emoji
            med.colorHex          = form.colorHex
            med.strength          = form.strength
            med.form              = form.form
            med.prescriber        = form.prescriber.isEmpty ? nil : form.prescriber
            med.schedule          = form.schedule
            med.dosesPerDay       = form.scheduleType == .asNeeded ? [] : form.doseTimes
            med.startDate         = Calendar.current.startOfDay(for: form.startDate)
            med.endDate           = form.hasEndDate ? Calendar.current.startOfDay(for: form.endDate) : nil
            med.notes             = form.notes.isEmpty ? nil : form.notes
            med.pillCount         = form.trackInventory ? form.pillCount : nil
            med.pillsPerDose      = form.pillsPerDose
            med.lowStockThreshold = form.lowStockThreshold
            onSave(med)
        } else {
            onSave(Medication(
                name:              trimmed,
                emoji:             form.emoji,
                colorHex:          form.colorHex,
                strength:          form.strength,
                form:              form.form,
                prescriber:        form.prescriber.isEmpty ? nil : form.prescriber,
                schedule:          form.schedule,
                dosesPerDay:       form.scheduleType == .asNeeded ? [] : form.doseTimes,
                startDate:         form.startDate,
                endDate:           form.hasEndDate ? form.endDate : nil,
                notes:             form.notes.isEmpty ? nil : form.notes,
                pillCount:         form.trackInventory ? form.pillCount : nil,
                pillsPerDose:      form.pillsPerDose,
                lowStockThreshold: form.lowStockThreshold
            ))
        }
    }
}

// MARK: - Symbol list

private let medSymbols: [String] = [
    "pill.fill", "pills.fill", "cross.fill", "cross.vial.fill",
    "syringe.fill", "stethoscope", "waveform.path.ecg",
    "heart.fill", "lungs.fill", "brain.head.profile",
    "bandage.fill", "eye.fill", "ear.fill",
    "drop.fill", "drop.circle.fill",
    "sun.max.fill", "moon.fill", "leaf.fill",
    "figure.walk", "figure.run", "figure.yoga",
    "bed.double.fill", "thermometer.medium",
    "allergens.fill", "microbe.fill",
    "bolt.heart.fill", "hand.raised.fill",
]

// MARK: - Previews

#if DEBUG
#Preview("Add medication") {
    AddEditMedicationView(onSave: { _ in }, onCancel: {})
}

#Preview("Edit medication") {
    let med = Medication(name: "Metformin", strength: "500 mg", form: .tablet,
                         schedule: .daily,
                         dosesPerDay: [Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!])
    return AddEditMedicationView(existing: med, onSave: { _ in }, onCancel: {})
}
#endif
