import Foundation
import SwiftData

#if DEBUG

/// Seeded realistic data for Previews and DEBUG first-launch.
enum MockData {

    // MARK: - Habits

    static let habits: [Habit] = [
        Habit(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            name: "Morning Run",
            emoji: "figure.run",
            colorHex: "34C759",
            schedule: .daily,
            targetCount: 1,
            sortOrder: 0
        ),
        Habit(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000002")!,
            name: "Read",
            emoji: "book.fill",
            colorHex: "007AFF",
            schedule: .daily,
            targetCount: 1,
            sortOrder: 1
        ),
        Habit(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000003")!,
            name: "Meditation",
            emoji: "figure.yoga",
            colorHex: "AF52DE",
            schedule: .weekdays,
            targetCount: 1,
            sortOrder: 2
        ),
        Habit(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000004")!,
            name: "Strength Training",
            emoji: "figure.strengthtraining.traditional",
            colorHex: "FF9500",
            schedule: .timesPerWeek(3),
            targetCount: 1,
            sortOrder: 3
        ),
        Habit(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000005")!,
            name: "Water (8 glasses)",
            emoji: "drop.fill",
            colorHex: "5AC8FA",
            schedule: .daily,
            targetCount: 8,
            sortOrder: 4
        ),
        Habit(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000006")!,
            name: "Journaling",
            emoji: "pencil",
            colorHex: "FF2D55",
            schedule: .customDays([0, 3, 6]),
            targetCount: 1,
            sortOrder: 5
        ),
    ]

    // MARK: - Completions

    /// Generates ~180 days of realistic completion data.
    static func completions(for habits: [Habit]) -> [HabitCompletion] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var all: [HabitCompletion] = []

        for habit in habits {
            var rng = SeededRNG(seed: habit.id.hashValue)

            for dayOffset in (-179)...0 {
                guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
                guard habit.schedule.isDue(on: date, calendar: calendar) else { continue }

                let chance = completionChance(habit: habit, dayOffset: dayOffset, rng: &rng)
                guard rng.nextDouble() < chance else { continue }

                let count: Int
                if habit.targetCount > 1 {
                    let raw = Int(ceil(Double(habit.targetCount) * rng.nextDouble()))
                    count = max(1, raw)
                } else {
                    count = 1
                }

                all.append(HabitCompletion(
                    id: UUID(),
                    habitID: habit.id,
                    date: date,
                    count: count
                ))
            }
        }
        return all
    }

    // MARK: - Medications

    static let medications: [Medication] = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: today)! }
        func time(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: today)! }

        return [
            Medication(
                id: UUID(uuidString: "00000002-0000-0000-0000-000000000001")!,
                name: "Metformin",
                emoji: "pill.fill",
                colorHex: "007AFF",
                strength: "500 mg",
                form: .tablet,
                schedule: .daily,
                dosesPerDay: [time(8), time(20)],
                startDate: daysAgo(89),
                sortOrder: 0
            ),
            Medication(
                id: UUID(uuidString: "00000002-0000-0000-0000-000000000002")!,
                name: "Vitamin D",
                emoji: "sun.max.fill",
                colorHex: "FF9500",
                strength: "2000 IU",
                form: .tablet,
                schedule: .daily,
                dosesPerDay: [time(9)],
                startDate: daysAgo(59),
                sortOrder: 1
            ),
            Medication(
                id: UUID(uuidString: "00000002-0000-0000-0000-000000000003")!,
                name: "Omega-3",
                emoji: "drop.fill",
                colorHex: "34C759",
                strength: "1000 mg",
                form: .capsule,
                schedule: .weekdays,
                dosesPerDay: [time(12)],
                startDate: daysAgo(29),
                sortOrder: 2
            ),
        ]
    }()

    static func medicationDoses(for medications: [Medication]) -> [MedicationDose] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var all: [MedicationDose] = []

        for med in medications {
            if case .asNeeded = med.schedule { continue }
            guard !med.dosesPerDay.isEmpty else { continue }

            var rng = SeededRNG(seed: med.id.hashValue &+ 200)

            for dayOffset in (-89)...(-1) {
                guard let date = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }
                guard date >= med.startDate else { continue }
                guard med.schedule.isDue(on: date, calendar: cal) else { continue }

                let weekIndex = (-dayOffset) / 7
                let adherence = min(0.97, max(0.55, 0.88 + sin(Double(weekIndex) * 0.7) * 0.12))

                for doseTime in med.dosesPerDay {
                    let comps = cal.dateComponents([.hour, .minute], from: doseTime)
                    let scheduledAt = cal.date(
                        bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0,
                        second: 0, of: date
                    ) ?? date

                    let roll = rng.nextDouble()
                    let status: DoseStatus
                    let takenAt: Date?
                    if roll < adherence {
                        status  = .taken
                        takenAt = scheduledAt.addingTimeInterval(rng.nextDouble() * 900)
                    } else if rng.nextDouble() < 0.4 {
                        status  = .skipped
                        takenAt = nil
                    } else {
                        status  = .missed
                        takenAt = nil
                    }
                    all.append(MedicationDose(medicationID: med.id, scheduledAt: scheduledAt,
                                              takenAt: takenAt, status: status))
                }
            }

            // Today's doses: pending
            if med.schedule.isDue(on: today, calendar: cal) {
                for doseTime in med.dosesPerDay {
                    let comps = cal.dateComponents([.hour, .minute], from: doseTime)
                    let scheduledAt = cal.date(
                        bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0,
                        second: 0, of: today
                    ) ?? today
                    all.append(MedicationDose(medicationID: med.id, scheduledAt: scheduledAt))
                }
            }
        }
        return all
    }

    // MARK: - In-memory ModelContainer for Previews

    static var previewContainer: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Habit.self, HabitCompletion.self, Medication.self, MedicationDose.self,
            configurations: config
        )
        let context = ModelContext(container)
        let seededHabits = MockData.habits
        seededHabits.forEach { context.insert($0) }
        MockData.completions(for: seededHabits).forEach { context.insert($0) }
        let seededMeds = MockData.medications
        seededMeds.forEach { context.insert($0) }
        MockData.medicationDoses(for: seededMeds).forEach { context.insert($0) }
        try! context.save()
        return container
    }()

    // MARK: - Private

    private static func completionChance(habit: Habit, dayOffset: Int, rng: inout SeededRNG) -> Double {
        let base: Double
        switch habit.schedule {
        case .daily:      base = 0.75
        case .weekdays:   base = 0.80
        case .customDays: base = 0.70
        case .timesPerWeek: base = 0.65
        }
        let weekIndex = (-dayOffset) / 7
        let slumpCycle = sin(Double(weekIndex) * 0.9) * 0.15
        return min(0.97, max(0.3, base + slumpCycle))
    }
}

// MARK: - Mood entries

extension MockData {

    /// 90 days of realistic mood entries — higher on days habits were completed.
    static func moodEntries(for habits: [Habit]) -> [MoodEntry] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var rng = SeededRNG(seed: 42)
        var entries: [MoodEntry] = []

        let completionDays: Set<Date> = {
            var days = Set<Date>()
            for habit in habits {
                for offset in 0..<90 {
                    guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
                    if habit.schedule.isDue(on: day, calendar: cal) && rng.nextDouble() < 0.82 {
                        days.insert(day)
                    }
                }
            }
            return days
        }()

        for offset in 0..<90 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            guard rng.nextDouble() < 0.75 else { continue }   // ~75% days have a mood log

            let didComplete = completionDays.contains(day)
            // Mood skews higher on completion days (3–5) vs skipped days (1–4)
            let rawScore: Int
            if didComplete {
                rawScore = Int((rng.nextDouble() * 2.5) + 2.5).clamped(to: 1...5)
            } else {
                rawScore = Int((rng.nextDouble() * 3.0) + 1.0).clamped(to: 1...5)
            }
            let level = MoodLevel(rawValue: rawScore) ?? .okay
            let logTime = day.addingTimeInterval(rng.nextDouble() * 3600 * 14 + 3600 * 8)
            entries.append(MoodEntry(date: logTime, level: level))
        }
        return entries
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { min(max(self, range.lowerBound), range.upperBound) }
}

// MARK: - Deterministic seeded PRNG (xorshift64)

struct SeededRNG {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed &+ 1))
        if state == 0 { state = 12345 }
        _ = nextDouble()
    }

    mutating func nextDouble() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state) / Double(UInt64.max)
    }
}

#endif
