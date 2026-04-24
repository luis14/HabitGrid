import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Export / Import DTOs

struct ExportData: Codable {
    var version: Int = 2
    var exportedAt: Date
    var habits: [HabitDTO]
    var completions: [CompletionDTO]
    var medications: [MedicationDTO]?

    struct HabitDTO: Codable {
        var id: UUID
        var name: String
        var emoji: String
        var colorHex: String
        var schedule: HabitSchedule
        var targetCount: Int
        var reminderTime: Date?
        var createdAt: Date
        var archivedAt: Date?
        var sortOrder: Int
    }

    struct CompletionDTO: Codable {
        var id: UUID
        var habitID: UUID
        var date: Date
        var count: Int
        var note: String?
    }

    struct MedicationDTO: Codable {
        var id: UUID
        var name: String
        var emoji: String
        var colorHex: String
        var strength: String
        var formRaw: String
        var schedule: MedicationSchedule
        var dosesPerDay: [Date]
        var startDate: Date
        var endDate: Date?
        var prescriber: String?
        var notes: String?
        var sortOrder: Int
    }
}

// MARK: - View

struct SettingsView: View {

    @Environment(HabitStore.self)      private var store
    @Environment(MedicationStore.self) private var medStore
    @Environment(\.modelContext) private var modelContext

    @AppStorage("weekStartDay")   private var weekStartDay: Int = 0  // 0=Sun, 1=Mon
    @AppStorage("themeOverride")  private var themeOverride: String = "system"
    @AppStorage("hasOnboarded")   private var hasOnboarded: Bool = false

    @State private var showResetAlert  = false
    @State private var exportItem: ExportItem? = nil
    @State private var showImporter    = false
    @State private var importResult    = ""
    @State private var showImportAlert = false
    @State private var notifGranted    = false
    @State private var resetError: String?

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                calendarSection
                notificationsSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
        }
        .task {
            notifGranted = await NotificationService.shared.isAuthorised
        }
        .fileExporter(
            isPresented: Binding(get: { exportItem != nil }, set: { if !$0 { exportItem = nil } }),
            document: exportItem,
            contentType: .json,
            defaultFilename: "habitgrid-export"
        ) { _ in exportItem = nil }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result: result)
        }
        .alert("Import result", isPresented: $showImportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importResult)
        }
        .alert("Reset all data?", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) { resetAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete every habit and all completion history. This cannot be undone.")
        }
        .alert("Reset failed", isPresented: Binding(
            get: { resetError != nil },
            set: { if !$0 { resetError = nil } }
        )) {
            Button("OK", role: .cancel) { resetError = nil }
        } message: {
            Text(resetError ?? "")
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $themeOverride) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
        }
    }

    private var calendarSection: some View {
        Section("Calendar") {
            Picker("Week starts on", selection: $weekStartDay) {
                Text("Sunday").tag(0)
                Text("Monday").tag(1)
            }
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            HStack {
                Label(notifGranted ? "Notifications enabled" : "Notifications disabled",
                      systemImage: notifGranted ? "bell.fill" : "bell.slash.fill")
                    .foregroundStyle(notifGranted ? .green : .secondary)
                Spacer()
                if !notifGranted {
                    Button("Enable") {
                        Task {
                            notifGranted = await NotificationService.shared.requestPermission()
                        }
                    }
                    .font(.caption)
                }
            }
            if notifGranted {
                Button("Reschedule habit reminders") {
                    Task {
                        await NotificationService.shared.rescheduleAll(habits: store.activeHabits)
                    }
                }
                Button("Reschedule medication reminders") {
                    Task {
                        await NotificationService.shared.rescheduleAll(medications: medStore.activeMedications)
                    }
                }
            }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            Button {
                exportItem = buildExport()
            } label: {
                Label("Export to JSON", systemImage: "square.and.arrow.up")
            }

            Button {
                showImporter = true
            } label: {
                Label("Import from JSON", systemImage: "square.and.arrow.down")
            }

            Button(role: .destructive) {
                showResetAlert = true
            } label: {
                Label("Reset all data…", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Build", value: appBuild)
            Button("View onboarding again") {
                hasOnboarded = false
            }
        }
    }

    // MARK: - Export

    private func buildExport() -> ExportItem? {
        let habitDTOs = store.activeHabits.map { h in
            ExportData.HabitDTO(
                id: h.id, name: h.name, emoji: h.emoji, colorHex: h.colorHex,
                schedule: h.schedule, targetCount: h.targetCount,
                reminderTime: h.reminderTime, createdAt: h.createdAt,
                archivedAt: h.archivedAt, sortOrder: h.sortOrder
            )
        }

        var compDTOs: [ExportData.CompletionDTO] = []
        for habit in store.activeHabits {
            let cal = Calendar.current
            let start = cal.date(byAdding: .day, value: -365, to: Date()) ?? Date()
            let comps = (try? store.completions(for: habit, from: start, to: Date())) ?? []
            compDTOs += comps.map {
                ExportData.CompletionDTO(id: $0.id, habitID: $0.habitID,
                                        date: $0.date, count: $0.count, note: $0.note)
            }
        }

        let medDTOs = medStore.activeMedications.map { m in
            ExportData.MedicationDTO(
                id: m.id, name: m.name, emoji: m.emoji, colorHex: m.colorHex,
                strength: m.strength, formRaw: m.formRaw, schedule: m.schedule,
                dosesPerDay: m.dosesPerDay, startDate: m.startDate,
                endDate: m.endDate, prescriber: m.prescriber,
                notes: m.notes, sortOrder: m.sortOrder
            )
        }

        let data = ExportData(exportedAt: Date(), habits: habitDTOs, completions: compDTOs, medications: medDTOs)
        guard let json = try? JSONEncoder().encode(data) else { return nil }
        return ExportItem(data: json)
    }

    // MARK: - Import

    private func handleImport(result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let raw = try Data(contentsOf: url)
            let export = try JSONDecoder().decode(ExportData.self, from: raw)

            var imported = 0
            let existingIDs = Set(store.activeHabits.map(\.id))

            for dto in export.habits where !existingIDs.contains(dto.id) {
                let habit = Habit(
                    id: dto.id, name: dto.name, emoji: dto.emoji,
                    colorHex: dto.colorHex, schedule: dto.schedule,
                    targetCount: dto.targetCount, reminderTime: dto.reminderTime,
                    createdAt: dto.createdAt, archivedAt: dto.archivedAt,
                    sortOrder: dto.sortOrder
                )
                try? store.addHabit(habit)
                imported += 1
            }

            for dto in export.completions {
                let habitID = dto.habitID
                let descriptor = FetchDescriptor<HabitCompletion>(
                    predicate: #Predicate { $0.habitID == habitID && $0.date == dto.date }
                )
                if (try? modelContext.fetch(descriptor).first) == nil {
                    modelContext.insert(HabitCompletion(
                        id: dto.id, habitID: dto.habitID,
                        date: dto.date, count: dto.count, note: dto.note
                    ))
                }
            }
            try? modelContext.save()

            importResult = "Imported \(imported) new habit(s) and \(export.completions.count) completion record(s)."
        } catch {
            importResult = "Import failed: \(error.localizedDescription)"
        }
        showImportAlert = true
    }

    // MARK: - Reset

    private func resetAllData() {
        do {
            for habit in store.activeHabits + store.archivedHabits {
                try store.deleteHabit(habit)
            }
            for med in medStore.activeMedications + medStore.archivedMedications {
                try medStore.deleteMedication(med)
            }
        } catch {
            resetError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

// MARK: - FileDocument wrapper for export

struct ExportItem: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    SettingsView()
        .environment(HabitStore(context: MockData.previewContainer.mainContext))
        .environment(MedicationStore(context: MockData.previewContainer.mainContext))
        .modelContainer(MockData.previewContainer)
}
#endif
