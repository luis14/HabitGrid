import AppIntents
import SwiftData
import Foundation

struct LogHabitIntent: AppIntent {

    static let title: LocalizedStringResource = "Log Habit"
    static let description = IntentDescription("Mark a habit as complete for today.")

    @Parameter(title: "Habit Name", requestValueDialog: IntentDialog("Which habit did you complete?"))
    var habitName: String

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        let container = try IntentModelContainer.make()
        let context = ModelContext(container)

        var descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.archivedAt == nil }
        )
        descriptor.fetchLimit = 200
        let habits = try context.fetch(descriptor)

        guard let habit = habits.first(where: {
            $0.name.localizedCaseInsensitiveCompare(habitName) == .orderedSame
        }) else {
            throw IntentError.noHabitFound(habitName)
        }

        let day = Calendar.current.startOfDay(for: Date())
        let habitID = habit.id
        var compDescriptor = FetchDescriptor<HabitCompletion>(
            predicate: #Predicate { $0.habitID == habitID && $0.date == day }
        )
        compDescriptor.fetchLimit = 1
        let existing = try context.fetch(compDescriptor)

        if let entry = existing.first {
            entry.count += 1
        } else {
            context.insert(HabitCompletion(habitID: habitID, date: day, count: 1, note: nil))
        }
        try context.save()

        return .result(dialog: "Marked \(habit.name) as complete for today.")
    }
}

// MARK: - Errors

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case noHabitFound(String)
    case noMedicationFound(String)
    case noPendingDose(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noHabitFound(let name):
            return "No active habit named '\(name)' was found."
        case .noMedicationFound(let name):
            return "No active medication named '\(name)' was found."
        case .noPendingDose(let name):
            return "No pending dose found for '\(name)' today."
        }
    }
}

// MARK: - Shared container helper

enum IntentModelContainer {
    static func make() throws -> ModelContainer {
        let schema = Schema([
            Habit.self, HabitCompletion.self, MoodEntry.self,
            Medication.self, MedicationDose.self
        ])
        if let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.habitgrid.shared"
        ) {
            let config = ModelConfiguration(schema: schema, url: url.appendingPathComponent("default.store"))
            return try ModelContainer(for: schema, configurations: config)
        }
        return try ModelContainer(for: schema)
    }
}
