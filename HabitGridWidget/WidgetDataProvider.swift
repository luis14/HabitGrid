import Foundation
import SwiftData

let habitGridAppGroupID = "group.com.habitgrid.shared"

// MARK: - Snapshot

struct WidgetSnapshot {
    let completedToday: Int
    let totalToday: Int
    let topHabits: [HabitRow]
    let habitGrids: [HabitGridRow]
    let date: Date

    struct HabitRow: Identifiable {
        let id: UUID
        let name: String
        let colorHex: String
        let isComplete: Bool
    }

    /// One row in the large grid widget — 28 days of completion data.
    struct HabitGridRow: Identifiable {
        let id: UUID
        let name: String
        let emoji: String
        let colorHex: String
        /// True for each of the last 28 days (index 0 = 27 days ago, index 27 = today).
        let completed: [Bool]
    }

    var progress: Double {
        guard totalToday > 0 else { return 0 }
        return Double(completedToday) / Double(totalToday)
    }

    static let placeholder: WidgetSnapshot = {
        let rows: [HabitGridRow] = [
            ("Morning Run", "figure.run",  "34C759"),
            ("Meditation",  "figure.yoga", "AF52DE"),
            ("Read",        "book.fill",   "007AFF"),
            ("Water",       "drop.fill",   "5AC8FA"),
        ].map { name, emoji, hex in
            HabitGridRow(id: UUID(), name: name, emoji: emoji, colorHex: hex,
                         completed: (0..<28).map { $0 % 3 != 2 })
        }
        return WidgetSnapshot(
            completedToday: 3,
            totalToday: 7,
            topHabits: [
                HabitRow(id: UUID(), name: "Morning Run",  colorHex: "34C759", isComplete: true),
                HabitRow(id: UUID(), name: "Meditation",   colorHex: "007AFF", isComplete: true),
                HabitRow(id: UUID(), name: "Read 30 min",  colorHex: "FF9500", isComplete: true),
                HabitRow(id: UUID(), name: "Drink Water",  colorHex: "5AC8FA", isComplete: false),
                HabitRow(id: UUID(), name: "Stretch",      colorHex: "AF52DE", isComplete: false),
            ],
            habitGrids: rows,
            date: .now
        )
    }()
}

// MARK: - Provider

enum WidgetDataProvider {
    static func snapshot() -> WidgetSnapshot {
        guard let container = makeContainer() else { return .placeholder }
        return load(context: ModelContext(container))
    }

    // MARK: - Private

    private static func makeContainer() -> ModelContainer? {
        let schema = Schema([
            Habit.self, HabitCompletion.self, MoodEntry.self,
            Medication.self, MedicationDose.self
        ])
        // Prefer App Group so the widget reads the same store as the main app.
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: habitGridAppGroupID) != nil {
            let config = ModelConfiguration(
                schema: schema,
                allowsSave: false,
                groupContainer: .identifier(habitGridAppGroupID)
            )
            if let container = try? ModelContainer(for: schema, configurations: config) {
                return container
            }
        }
        // Simulator fallback: standard Application Support location.
        let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try? ModelContainer(for: schema, configurations: fallback)
    }

    private static func load(context: ModelContext) -> WidgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var habitDesc = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        habitDesc.fetchLimit = 20
        let habits = (try? context.fetch(habitDesc)) ?? []
        let dueHabits = habits.filter { $0.schedule.isDue(on: today, calendar: calendar) }

        guard !dueHabits.isEmpty else {
            return WidgetSnapshot(completedToday: 0, totalToday: 0, topHabits: [], habitGrids: [], date: today)
        }

        var completionDesc = FetchDescriptor<HabitCompletion>(
            predicate: #Predicate { $0.date == today }
        )
        completionDesc.fetchLimit = 100
        let completions = (try? context.fetch(completionDesc)) ?? []
        let countByHabit = Dictionary(grouping: completions, by: \.habitID)
            .mapValues { $0.reduce(0) { $0 + $1.count } }

        let rows = dueHabits.map { habit in
            WidgetSnapshot.HabitRow(
                id: habit.id,
                name: habit.name,
                colorHex: habit.colorHex,
                isComplete: (countByHabit[habit.id] ?? 0) >= max(1, habit.targetCount)
            )
        }

        // Build 28-day grids for top 4 active habits.
        let gridHabits = Array(habits.prefix(4))
        guard let gridStart = calendar.date(byAdding: .day, value: -27, to: today) else {
            return WidgetSnapshot(completedToday: rows.filter(\.isComplete).count,
                                  totalToday: dueHabits.count,
                                  topHabits: Array(rows.prefix(5)),
                                  habitGrids: [],
                                  date: today)
        }

        var allCompDesc = FetchDescriptor<HabitCompletion>(
            predicate: #Predicate { $0.date >= gridStart && $0.date <= today }
        )
        allCompDesc.fetchLimit = 500
        let allComps = (try? context.fetch(allCompDesc)) ?? []
        // Use a struct key instead of string concatenation to avoid locale/format issues.
        struct CompKey: Hashable { let habitID: UUID; let date: Date }
        let compSet = Set(allComps.filter { $0.count > 0 }.map { CompKey(habitID: $0.habitID, date: $0.date) })

        let habitGrids = gridHabits.map { habit in
            let days: [Bool] = (0..<28).map { offset in
                guard let day = calendar.date(byAdding: .day, value: offset - 27, to: today) else { return false }
                let key = CompKey(habitID: habit.id, date: calendar.startOfDay(for: day))
                return compSet.contains(key)
            }
            return WidgetSnapshot.HabitGridRow(
                id: habit.id,
                name: habit.name,
                emoji: habit.emoji,
                colorHex: habit.colorHex,
                completed: days
            )
        }

        return WidgetSnapshot(
            completedToday: rows.filter(\.isComplete).count,
            totalToday: dueHabits.count,
            topHabits: Array(rows.prefix(5)),
            habitGrids: habitGrids,
            date: today
        )
    }
}
