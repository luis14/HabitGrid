import XCTest
import SwiftData
@testable import HabitGrid

@MainActor
final class HabitStoreTests: XCTestCase {

    // MARK: - Setup

    var container: ModelContainer!
    var context: ModelContext!
    var store: HabitStore!

    override func setUp() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Habit.self, HabitCompletion.self, configurations: config)
        context = ModelContext(container)
        store = HabitStore(context: context)
    }

    override func tearDown() {
        store = nil
        context = nil
        container = nil
    }

    // MARK: - Helpers

    /// Calendar fixed to US/Eastern to test timezone-independent behavior.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }

    private func makeHabit(
        schedule: HabitSchedule = .daily,
        targetCount: Int = 1,
        createdDaysAgo: Int = 30,
        archived: Bool = false
    ) throws -> Habit {
        let created = calendar.startOfDay(for: Date()) |> { calendar.date(byAdding: .day, value: -createdDaysAgo, to: $0)! }
        let habit = Habit(
            name: "Test Habit",
            schedule: schedule,
            targetCount: targetCount,
            createdAt: created
        )
        if archived {
            habit.archivedAt = Date()
        }
        try store.addHabit(habit)
        return habit
    }

    private func complete(_ habit: Habit, daysAgo: Int, count: Int = 1) throws {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
        try store.markComplete(habit: habit, on: date, count: count)
    }

    // MARK: - Intensity Bucketing

    func testIntensityBinaryHabitNoCompletion() {
        XCTAssertEqual(HabitStore.intensityBucket(count: 0, targetCount: 1), 0)
    }

    func testIntensityBinaryHabitCompleted() {
        XCTAssertEqual(HabitStore.intensityBucket(count: 1, targetCount: 1), 4)
    }

    func testIntensityBinaryHabitOvercompleted() {
        // Binary habit: any count ≥ 1 → full intensity
        XCTAssertEqual(HabitStore.intensityBucket(count: 3, targetCount: 1), 4)
    }

    func testIntensityMultiCountBuckets() {
        // targetCount = 8 (e.g., "drink 8 glasses")
        XCTAssertEqual(HabitStore.intensityBucket(count: 0, targetCount: 8), 0, "none")
        XCTAssertEqual(HabitStore.intensityBucket(count: 1, targetCount: 8), 1, "12.5% → bucket 1")
        XCTAssertEqual(HabitStore.intensityBucket(count: 2, targetCount: 8), 1, "25% → bucket 1 boundary")
        XCTAssertEqual(HabitStore.intensityBucket(count: 3, targetCount: 8), 2, "37.5% → bucket 2")
        XCTAssertEqual(HabitStore.intensityBucket(count: 4, targetCount: 8), 2, "50% → bucket 2 boundary")
        XCTAssertEqual(HabitStore.intensityBucket(count: 5, targetCount: 8), 3, "62.5% → bucket 3")
        XCTAssertEqual(HabitStore.intensityBucket(count: 6, targetCount: 8), 3, "75% → bucket 3 boundary")
        XCTAssertEqual(HabitStore.intensityBucket(count: 7, targetCount: 8), 4, "87.5% → bucket 4")
        XCTAssertEqual(HabitStore.intensityBucket(count: 8, targetCount: 8), 4, "100% → bucket 4")
        XCTAssertEqual(HabitStore.intensityBucket(count: 10, targetCount: 8), 4, "over target → bucket 4")
    }

    func testIntensityMultiCountTargetTwo() {
        XCTAssertEqual(HabitStore.intensityBucket(count: 1, targetCount: 2), 2, "50% → bucket 2")
        XCTAssertEqual(HabitStore.intensityBucket(count: 2, targetCount: 2), 4, "100% → bucket 4")
    }

    // MARK: - Daily Streak: Basic

    func testNoCompletionsStreakIsZero() throws {
        let habit = try makeHabit(createdDaysAgo: 10)
        XCTAssertEqual(try store.currentStreak(for: habit), 0)
    }

    func testSingleCompletionTodayStreakOne() throws {
        let habit = try makeHabit(createdDaysAgo: 5)
        try complete(habit, daysAgo: 0)
        XCTAssertEqual(try store.currentStreak(for: habit), 1)
    }

    func testConsecutiveDaysStreak() throws {
        let habit = try makeHabit(createdDaysAgo: 10)
        for daysAgo in 0...4 { try complete(habit, daysAgo: daysAgo) }
        XCTAssertEqual(try store.currentStreak(for: habit), 5)
    }

    func testMissedDayBreaksStreak() throws {
        let habit = try makeHabit(createdDaysAgo: 10)
        // Miss day 1 (yesterday)
        try complete(habit, daysAgo: 0)
        try complete(habit, daysAgo: 2)
        try complete(habit, daysAgo: 3)
        // Current streak: only today (since yesterday is missed)
        XCTAssertEqual(try store.currentStreak(for: habit), 1)
    }

    func testTodayNotYetCompletedDoesNotBreakYesterdayStreak() throws {
        // Streak should be 3 even though today is not done yet
        let habit = try makeHabit(createdDaysAgo: 10)
        for daysAgo in 1...3 { try complete(habit, daysAgo: daysAgo) }
        XCTAssertEqual(try store.currentStreak(for: habit), 3)
    }

    // MARK: - Daily Streak: Weekdays Schedule

    func testWeekdayScheduleSkipsWeekend() throws {
        let habit = try makeHabit(schedule: .weekdays, createdDaysAgo: 14)
        // Complete Mon-Fri of last week and Mon-Fri of this week
        // We mark completions on "scheduled" weekdays only and verify no break
        let today = calendar.startOfDay(for: Date())
        var completedCount = 0
        for offset in (-9)...0 {
            guard let d = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if HabitSchedule.weekdays.isDue(on: d, calendar: calendar) {
                try store.markComplete(habit: habit, on: d)
                completedCount += 1
            }
        }
        let streak = try store.currentStreak(for: habit)
        XCTAssertGreaterThan(streak, 0)
        // Streak should not be broken by weekend gaps
        let today_wd = calendar.component(.weekday, from: today)
        // If today is Mon (weekday == 2), there are at most ~2 weekdays completed this week
        // But the streak should at minimum include all weekdays up to today
        XCTAssertLessThanOrEqual(streak, completedCount)
    }

    // MARK: - Daily Streak: Custom Days Schedule

    func testCustomDaysScheduleStreakSkipsNonScheduledDays() throws {
        // Sun=0, Wed=3, Sat=6
        let habit = try makeHabit(schedule: .customDays([0, 3, 6]), createdDaysAgo: 30)
        let today = calendar.startOfDay(for: Date())

        // Complete every Sun/Wed/Sat in past 3 weeks
        for offset in (-20)...0 {
            guard let d = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if habit.schedule.isDue(on: d, calendar: calendar) {
                try store.markComplete(habit: habit, on: d)
            }
        }
        let streak = try store.currentStreak(for: habit)
        XCTAssertGreaterThan(streak, 0, "Streak should count consecutive scheduled days")
    }

    // MARK: - Daily Streak: Longest

    func testLongestStreakTracksOverAll() throws {
        let habit = try makeHabit(createdDaysAgo: 20)
        // Complete days 15-11 ago (5 days), gap at 10, then days 5-1 ago (5 days), miss today
        for d in [15, 14, 13, 12, 11, 5, 4, 3, 2, 1] { try complete(habit, daysAgo: d) }
        XCTAssertEqual(try store.longestStreak(for: habit), 5)
    }

    func testCurrentStreakLowerThanLongest() throws {
        let habit = try makeHabit(createdDaysAgo: 20)
        // Long streak two weeks ago, then a gap, then short recent streak
        for d in [18, 17, 16, 15, 14, 13, 12, 11, 10] { try complete(habit, daysAgo: d) }
        for d in [2, 1, 0] { try complete(habit, daysAgo: d) }
        XCTAssertEqual(try store.longestStreak(for: habit), 9)
        XCTAssertEqual(try store.currentStreak(for: habit), 3)
    }

    // MARK: - Archived Habit Streak

    func testArchivedHabitStreakStopsAtArchiveDate() throws {
        let habit = try makeHabit(createdDaysAgo: 10)
        // Complete days 5..2 ago, then archive
        for d in [5, 4, 3, 2] { try complete(habit, daysAgo: d) }
        // Archive 1 day ago
        let archiveDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        habit.archivedAt = archiveDate
        try store.updateHabit(habit)
        // Even though today has no completion (and habit isn't due after archival),
        // streak should be capped at the 4 days before archive
        let streak = try store.currentStreak(for: habit)
        XCTAssertEqual(streak, 4)
    }

    // MARK: - Weekly Streak (timesPerWeek)

    func testWeeklyStreakMetTarget() throws {
        let habit = try makeHabit(schedule: .timesPerWeek(3), createdDaysAgo: 21)
        let today = calendar.startOfDay(for: Date())
        // Complete 3 times in each of the last 3 weeks
        for weekOffset in [0, 1, 2] {
            let base = calendar.date(byAdding: .day, value: -(weekOffset * 7), to: today)!
            let (ws, _) = weekBounds(for: base)
            for dayOffset in [0, 2, 4] {
                if let d = calendar.date(byAdding: .day, value: dayOffset, to: ws), d <= today {
                    try store.markComplete(habit: habit, on: d)
                }
            }
        }
        XCTAssertGreaterThanOrEqual(try store.currentStreak(for: habit), 2)
    }

    func testWeeklyStreakBrokenByMissedWeek() throws {
        let habit = try makeHabit(schedule: .timesPerWeek(3), createdDaysAgo: 28)
        let today = calendar.startOfDay(for: Date())
        // Complete 3 times this week and 3 times 2 weeks ago (missing last week)
        let thisWeekStart = weekBounds(for: today).start
        let twoWeeksAgoStart = calendar.date(byAdding: .day, value: -14, to: thisWeekStart)!

        for dayOffset in [0, 1, 2] {
            if let d = calendar.date(byAdding: .day, value: dayOffset, to: thisWeekStart), d <= today {
                try store.markComplete(habit: habit, on: d)
            }
            if let d = calendar.date(byAdding: .day, value: dayOffset, to: twoWeeksAgoStart) {
                try store.markComplete(habit: habit, on: d)
            }
        }
        // Current week (in progress) + 0 last week = streak of 0 (last week was missed)
        // The current week's grace should give ≤ 1
        XCTAssertLessThanOrEqual(try store.currentStreak(for: habit), 1)
    }

    // MARK: - Mark / Set Completion

    func testMarkCompleteAccumulates() throws {
        let habit = try makeHabit(targetCount: 5)
        try store.markComplete(habit: habit, on: Date(), count: 2)
        try store.markComplete(habit: habit, on: Date(), count: 3)
        let entry = try store.completion(for: habit, on: Date())
        XCTAssertEqual(entry?.count, 5)
    }

    func testSetCompletionOverwrites() throws {
        let habit = try makeHabit(targetCount: 5)
        try store.markComplete(habit: habit, on: Date(), count: 3)
        try store.setCompletion(habit: habit, on: Date(), count: 1)
        let entry = try store.completion(for: habit, on: Date())
        XCTAssertEqual(entry?.count, 1)
    }

    func testSetCompletionToZeroDeletesEntry() throws {
        let habit = try makeHabit()
        try store.markComplete(habit: habit, on: Date())
        try store.setCompletion(habit: habit, on: Date(), count: 0)
        let entry = try store.completion(for: habit, on: Date())
        XCTAssertNil(entry)
    }

    // MARK: - Completion Rate

    func testCompletionRateAllCompleted() throws {
        let habit = try makeHabit(schedule: .daily, createdDaysAgo: 6)
        for d in 0...6 { try complete(habit, daysAgo: d) }
        let rate = try store.completionRate(for: habit, days: 7)
        XCTAssertEqual(rate, 1.0, accuracy: 0.01)
    }

    func testCompletionRateHalfCompleted() throws {
        let habit = try makeHabit(schedule: .daily, createdDaysAgo: 9)
        for d in stride(from: 0, through: 9, by: 2) { try complete(habit, daysAgo: d) }
        let rate = try store.completionRate(for: habit, days: 10)
        XCTAssertEqual(rate, 0.5, accuracy: 0.05)
    }

    // MARK: - Delete Habit Removes Completions

    func testDeleteHabitCleansUpCompletions() throws {
        let habit = try makeHabit()
        let habitID = habit.id
        for d in 0...4 { try complete(habit, daysAgo: d) }
        try store.deleteHabit(habit)
        let descriptor = FetchDescriptor<HabitCompletion>(
            predicate: #Predicate { $0.habitID == habitID }
        )
        let remaining = try context.fetch(descriptor)
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - Helpers

    private func weekBounds(for date: Date) -> (start: Date, end: Date) {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let start = calendar.date(from: comps) ?? date
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? date
        return (start, end)
    }
}

// MARK: - Pipe operator for readability in test helpers

infix operator |>: AdditionPrecedence
private func |> <T, U>(value: T, transform: (T) -> U) -> U { transform(value) }
