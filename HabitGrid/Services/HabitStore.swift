import Foundation
import SwiftData
import Observation

/// Central service for all habit and completion CRUD operations.
/// Injectable via SwiftUI's `@Environment` so views can be previewed with `MockHabitStore`.
@Observable
final class HabitStore {

    @ObservationIgnored private var context: ModelContext

    // MARK: - Cached state (re-fetched on each mutation)

    private(set) var activeHabits: [Habit] = []
    private(set) var archivedHabits: [Habit] = []

    // MARK: - Init

    init(context: ModelContext) {
        self.context = context
        try? refreshHabits()
    }

    // MARK: - Habit CRUD

    func addHabit(_ habit: Habit) throws {
        habit.sortOrder = (activeHabits.last?.sortOrder ?? -1) + 1
        context.insert(habit)
        try save()
    }

    func updateHabit(_ habit: Habit) throws {
        try save()
    }

    func archiveHabit(_ habit: Habit) throws {
        habit.archivedAt = Date()
        try save()
    }

    func unarchiveHabit(_ habit: Habit) throws {
        habit.archivedAt = nil
        try save()
    }

    func deleteHabit(_ habit: Habit) throws {
        // Remove all completions first
        let habitID = habit.id
        let descriptor = FetchDescriptor<HabitCompletion>(
            predicate: #Predicate { $0.habitID == habitID }
        )
        let completions = (try? context.fetch(descriptor)) ?? []
        completions.forEach { context.delete($0) }
        context.delete(habit)
        try save()
    }

    func reorder(habits: [Habit]) throws {
        for (index, habit) in habits.enumerated() {
            habit.sortOrder = index
        }
        try save()
    }

    // MARK: - Completion CRUD

    /// Marks a habit complete on `date`, merging with an existing entry if one exists.
    func markComplete(habit: Habit, on date: Date = Date(), count: Int = 1, note: String? = nil) throws {
        let day = Calendar.current.startOfDay(for: date)
        let habitID = habit.id

        let descriptor = FetchDescriptor<HabitCompletion>(
            predicate: #Predicate { $0.habitID == habitID && $0.date == day }
        )
        let existing = try context.fetch(descriptor)

        if let entry = existing.first {
            entry.count += count
            if let note { entry.note = note }
        } else {
            context.insert(HabitCompletion(habitID: habitID, date: day, count: count, note: note))
        }
        try save()
    }

    /// Sets the completion count explicitly (use 0 to un-complete).
    func setCompletion(habit: Habit, on date: Date = Date(), count: Int, note: String? = nil) throws {
        let day = Calendar.current.startOfDay(for: date)
        let habitID = habit.id

        let descriptor = FetchDescriptor<HabitCompletion>(
            predicate: #Predicate { $0.habitID == habitID && $0.date == day }
        )
        let existing = try context.fetch(descriptor)

        if count <= 0 {
            existing.forEach { context.delete($0) }
        } else if let entry = existing.first {
            entry.count = count
            if let note { entry.note = note }
        } else {
            context.insert(HabitCompletion(habitID: habitID, date: day, count: count, note: note))
        }
        try save()
    }

    func deleteCompletion(habit: Habit, on date: Date) throws {
        try setCompletion(habit: habit, on: date, count: 0)
    }

    // MARK: - Queries

    func completions(for habit: Habit, from startDate: Date, to endDate: Date) throws -> [HabitCompletion] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.startOfDay(for: endDate)
        let habitID = habit.id

        var descriptor = FetchDescriptor<HabitCompletion>(
            predicate: #Predicate { $0.habitID == habitID && $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date)]
        )
        descriptor.fetchLimit = 400
        return try context.fetch(descriptor)
    }

    func completion(for habit: Habit, on date: Date) throws -> HabitCompletion? {
        let day = Calendar.current.startOfDay(for: date)
        let habitID = habit.id
        let descriptor = FetchDescriptor<HabitCompletion>(
            predicate: #Predicate { $0.habitID == habitID && $0.date == day }
        )
        return try context.fetch(descriptor).first
    }

    // MARK: - Streak

    func currentStreak(for habit: Habit) throws -> Int {
        switch habit.schedule {
        case .timesPerWeek(let target):
            return try weeklyStreak(for: habit, weeklyTarget: target)
        default:
            return try dailyStreak(for: habit)
        }
    }

    func longestStreak(for habit: Habit) throws -> Int {
        switch habit.schedule {
        case .timesPerWeek(let target):
            return try longestWeeklyStreak(for: habit, weeklyTarget: target)
        default:
            return try longestDailyStreak(for: habit)
        }
    }

    // MARK: - Intensity

    /// Returns a 0–4 intensity bucket for rendering the contribution graph.
    func intensity(for habit: Habit, on date: Date) throws -> Int {
        let entry = try completion(for: habit, on: date)
        let count = entry?.count ?? 0
        return Self.intensityBucket(count: count, targetCount: habit.targetCount)
    }

    /// Pure function — usable without a context for previews and tests.
    static func intensityBucket(count: Int, targetCount: Int) -> Int {
        guard count > 0 else { return 0 }
        guard targetCount > 1 else { return 4 }
        let ratio = Double(count) / Double(targetCount)
        switch ratio {
        case ..<0.25: return 1
        case 0.25..<0.5: return 2
        case 0.5..<0.75: return 3
        default: return 4
        }
    }

    // MARK: - Completion rate

    /// Completion rate for the last `days` days (only counts scheduled days).
    func completionRate(for habit: Habit, days: Int) throws -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return 0 }

        let comps = try completions(for: habit, from: start, to: today)
        let completedDays = Set(comps.filter { $0.count > 0 }.map { calendar.startOfDay(for: $0.date) })

        var scheduledCount = 0
        var completedCount = 0
        var cursor = start
        while cursor <= today {
            if habit.schedule.isDue(on: cursor, calendar: calendar) {
                scheduledCount += 1
                if completedDays.contains(cursor) { completedCount += 1 }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return scheduledCount == 0 ? 0 : Double(completedCount) / Double(scheduledCount)
    }

    // MARK: - Weekday breakdown

    /// Returns count of completions per weekday index 0 (Sun) … 6 (Sat).
    func weekdayBreakdown(for habit: Habit, days: Int = 90) throws -> [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return Array(repeating: 0, count: 7)
        }
        let comps = try completions(for: habit, from: start, to: today)
        var result = Array(repeating: 0, count: 7)
        for c in comps where c.count > 0 {
            let wd = calendar.component(.weekday, from: c.date) - 1 // 0-based
            result[wd] += 1
        }
        return result
    }

    // MARK: - Public refresh (called by seeding / debugging code)

    /// Re-fetches all habits from the persistent store into the cached arrays.
    func refresh() {
        try? refreshHabits()
    }

    // MARK: - Private helpers

    private func refreshHabits() throws {
        var active = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        active.fetchLimit = 200
        activeHabits = try context.fetch(active)

        var archived = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.archivedAt != nil },
            sortBy: [SortDescriptor(\.archivedAt, order: .reverse)]
        )
        archived.fetchLimit = 200
        archivedHabits = try context.fetch(archived)
    }

    private func save() throws {
        try context.save()
        try refreshHabits()
    }

    // MARK: - Daily streak

    private func dailyStreak(for habit: Habit) throws -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let archiveDay = habit.archivedAt.map { calendar.startOfDay(for: $0) }
        let endDate = archiveDay ?? today
        let createdDay = calendar.startOfDay(for: habit.createdAt)

        let comps = try completions(for: habit, from: habit.createdAt, to: endDate)
        let completedDays = Set(comps.filter { $0.count > 0 }.map { calendar.startOfDay(for: $0.date) })

        var checkDate = endDate
        // If today is scheduled but not yet done, don't break streak — just don't count it yet.
        if checkDate == today
            && habit.schedule.isDue(on: checkDate, calendar: calendar)
            && !completedDays.contains(checkDate) {
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { return 0 }
            checkDate = prev
        }

        var streak = 0
        while checkDate >= createdDay {
            if habit.schedule.isDue(on: checkDate, calendar: calendar) {
                if completedDays.contains(checkDate) {
                    streak += 1
                } else {
                    break
                }
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }
        return streak
    }

    private func longestDailyStreak(for habit: Habit) throws -> Int {
        let calendar = Calendar.current
        let endDate = habit.archivedAt.map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: Date())
        let createdDay = calendar.startOfDay(for: habit.createdAt)

        let comps = try completions(for: habit, from: habit.createdAt, to: endDate)
        let completedDays = Set(comps.filter { $0.count > 0 }.map { calendar.startOfDay(for: $0.date) })

        var longest = 0
        var current = 0
        var cursor = createdDay
        while cursor <= endDate {
            if habit.schedule.isDue(on: cursor, calendar: calendar) {
                if completedDays.contains(cursor) {
                    current += 1
                    longest = max(longest, current)
                } else {
                    current = 0
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return longest
    }

    // MARK: - Weekly streak (for timesPerWeek schedule)

    private func weeklyStreak(for habit: Habit, weeklyTarget: Int) throws -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let archiveDay = habit.archivedAt.map { calendar.startOfDay(for: $0) }
        let endDate = archiveDay ?? today

        var streak = 0
        // Walk backwards week by week
        var weekContaining = endDate
        while true {
            let (weekStart, weekEnd) = weekBounds(for: weekContaining, calendar: calendar)
            if weekStart < calendar.startOfDay(for: habit.createdAt) { break }

            let comps = try completions(for: habit, from: weekStart, to: min(weekEnd, endDate))
            let totalCount = comps.reduce(0) { $0 + $1.count }

            // Current week gets a grace period: we might not have finished it yet
            let isCurrentWeek = calendar.isDate(today, equalTo: weekContaining, toGranularity: .weekOfYear)
            if totalCount >= weeklyTarget {
                streak += 1
            } else if isCurrentWeek {
                // Week in progress, don't break streak yet; just don't count it
            } else {
                break
            }

            guard let prevWeek = calendar.date(byAdding: .day, value: -7, to: weekStart) else { break }
            weekContaining = prevWeek
        }
        return streak
    }

    private func longestWeeklyStreak(for habit: Habit, weeklyTarget: Int) throws -> Int {
        let calendar = Calendar.current
        let endDate = habit.archivedAt.map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: Date())
        let createdDay = calendar.startOfDay(for: habit.createdAt)
        let (firstWeekStart, _) = weekBounds(for: createdDay, calendar: calendar)

        var longest = 0
        var current = 0
        var weekStart = firstWeekStart

        while weekStart <= endDate {
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let comps = try completions(for: habit, from: weekStart, to: min(weekEnd, endDate))
            let total = comps.reduce(0) { $0 + $1.count }
            if total >= weeklyTarget {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
            guard let next = calendar.date(byAdding: .day, value: 7, to: weekStart) else { break }
            weekStart = next
        }
        return longest
    }

    private func weekBounds(for date: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let start = calendar.date(from: comps) ?? date
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? date
        return (start, end)
    }
}
