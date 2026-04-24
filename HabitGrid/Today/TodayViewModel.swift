import Foundation
import UIKit
import Observation

@Observable
final class TodayViewModel {

    // @ObservationIgnored because `store` itself is constant; we still track
    // store.activeHabits (and its children) through SwiftUI's thread-local
    // observer that captures all @Observable accesses during body evaluation.
    @ObservationIgnored private let store: HabitStore

    private(set) var todayCompletions: [UUID: Int] = [:]
    private(set) var streaks: [UUID: Int] = [:]
    private(set) var error: String? = nil

    init(store: HabitStore) {
        self.store = store
        refresh()
    }

    // MARK: - Derived state (computed so SwiftUI tracks store.activeHabits)

    var habitsForToday: [Habit] {
        let today = Calendar.current.startOfDay(for: Date())
        return store.activeHabits.filter { $0.schedule.isDue(on: today) }
    }

    var completedToday: Int {
        habitsForToday.filter { isComplete($0) }.count
    }

    var totalToday: Int { habitsForToday.count }

    var allDone: Bool { totalToday > 0 && completedToday == totalToday }

    var progress: Double {
        totalToday == 0 ? 0 : Double(completedToday) / Double(totalToday)
    }

    // MARK: - Per-habit helpers

    func currentCount(for habit: Habit) -> Int {
        todayCompletions[habit.id] ?? 0
    }

    func isComplete(_ habit: Habit) -> Bool {
        currentCount(for: habit) >= habit.targetCount
    }

    func streak(for habit: Habit) -> Int {
        streaks[habit.id] ?? 0
    }

    // MARK: - Actions

    /// Primary tap: toggle binary; increment multi-count.
    func tap(habit: Habit) {
        let count = currentCount(for: habit)
        do {
            if habit.targetCount == 1 {
                try store.setCompletion(habit: habit, on: Date(), count: count > 0 ? 0 : 1)
            } else {
                // Increment up to 2× target then wrap to 0
                let max = habit.targetCount * 2
                try store.setCompletion(habit: habit, on: Date(), count: count >= max ? 0 : count + 1)
            }
            impact(.medium)
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    /// Long-press confirmation: set exact count + optional note.
    func save(habit: Habit, count: Int, note: String) {
        do {
            try store.setCompletion(
                habit: habit,
                on: Date(),
                count: max(0, count),
                note: note.isEmpty ? nil : note
            )
            impact(.light)
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    // MARK: - Refresh cache

    func refresh() {
        let today = Calendar.current.startOfDay(for: Date())
        var comps: [UUID: Int] = [:]
        var stks: [UUID: Int] = [:]
        for habit in store.activeHabits {
            comps[habit.id] = (try? store.completion(for: habit, on: today))?.count ?? 0
            stks[habit.id] = (try? store.currentStreak(for: habit)) ?? 0
        }
        todayCompletions = comps
        streaks = stks
    }

    // MARK: - Private

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
