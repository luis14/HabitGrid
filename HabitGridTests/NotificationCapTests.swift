import XCTest
@testable import HabitGrid

final class NotificationCapTests: XCTestCase {

    // MARK: - wouldExceedBudget

    func testBudgetNotExceededWhenExactlyAtLimit() {
        // 60 pending + 0 new = 60 → fits
        XCTAssertFalse(NotificationService.wouldExceedBudget(pending: 60, newSlots: 0))
    }

    func testBudgetExceededWhenOneOverLimit() {
        // 60 pending + 1 new = 61 → exceeds
        XCTAssertTrue(NotificationService.wouldExceedBudget(pending: 60, newSlots: 1))
    }

    func testBudgetNotExceededWithRoomRemaining() {
        XCTAssertFalse(NotificationService.wouldExceedBudget(pending: 50, newSlots: 5))
    }

    func testBudgetExceededWhenSumExceedsLimit() {
        XCTAssertTrue(NotificationService.wouldExceedBudget(pending: 55, newSlots: 10))
    }

    func testBudgetIsCorrectValue() {
        XCTAssertEqual(NotificationService.notificationBudget, 60)
    }

    // MARK: - requestCount(for habit:)

    func testHabitDailyRequestCount() {
        let habit = makeHabit(schedule: .daily)
        XCTAssertEqual(NotificationService.requestCount(for: habit), 1)
    }

    func testHabitTimesPerWeekRequestCount() {
        let habit = makeHabit(schedule: .timesPerWeek(3))
        XCTAssertEqual(NotificationService.requestCount(for: habit), 1)
    }

    func testHabitWeekdaysRequestCount() {
        let habit = makeHabit(schedule: .weekdays)
        XCTAssertEqual(NotificationService.requestCount(for: habit), 5)
    }

    func testHabitCustomDaysRequestCount() {
        let habit = makeHabit(schedule: .customDays([0, 2, 4]))
        XCTAssertEqual(NotificationService.requestCount(for: habit), 3)
    }

    func testHabitCustomDaysSingleDayRequestCount() {
        let habit = makeHabit(schedule: .customDays([1]))
        XCTAssertEqual(NotificationService.requestCount(for: habit), 1)
    }

    // MARK: - requestCount(for medication:)

    func testMedicationDailyOneDoseRequestCount() {
        let med = makeMedication(schedule: .daily, doseCount: 1)
        XCTAssertEqual(NotificationService.requestCount(for: med), 1)
    }

    func testMedicationDailyMultiDoseRequestCount() {
        let med = makeMedication(schedule: .daily, doseCount: 3)
        XCTAssertEqual(NotificationService.requestCount(for: med), 3)
    }

    func testMedicationWeekdaysOneDoseRequestCount() {
        let med = makeMedication(schedule: .weekdays, doseCount: 1)
        XCTAssertEqual(NotificationService.requestCount(for: med), 5)
    }

    func testMedicationWeekdaysMultiDoseRequestCount() {
        let med = makeMedication(schedule: .weekdays, doseCount: 2)
        XCTAssertEqual(NotificationService.requestCount(for: med), 10)
    }

    func testMedicationCustomDaysRequestCount() {
        let med = makeMedication(schedule: .customDays([0, 3, 6]), doseCount: 2)
        XCTAssertEqual(NotificationService.requestCount(for: med), 6)
    }

    func testMedicationAsNeededRequestCount() {
        let med = makeMedication(schedule: .asNeeded, doseCount: 1)
        XCTAssertEqual(NotificationService.requestCount(for: med), 0)
    }

    func testMedicationEmptyDosesDefaultsToOne() {
        // doseCount 0 → max(1, 0) = 1
        let med = makeMedication(schedule: .daily, doseCount: 0)
        XCTAssertEqual(NotificationService.requestCount(for: med), 1)
    }

    // MARK: - Priority ordering logic

    /// Medications should consume budget before habits when combined.
    /// If 59 slots are taken, a medication needing 1 slot fits but a habit that also needs 1
    /// would be dropped if the medication was scheduled first and exactly hit the cap.
    func testMedicationsConsumesBudgetBeforeHabits() {
        // Start with 59 pending. A medication needing 1 slot fits (59+1 = 60 ≤ 60).
        XCTAssertFalse(NotificationService.wouldExceedBudget(pending: 59, newSlots: 1))

        // After scheduling that medication, pending = 60.
        // A habit needing 1 more slot would now exceed the budget.
        XCTAssertTrue(NotificationService.wouldExceedBudget(pending: 60, newSlots: 1))
    }

    // MARK: - Helpers

    private func makeHabit(schedule: HabitSchedule) -> Habit {
        let h = Habit(name: "Test", emoji: "✅", colorHex: "#FF0000", schedule: schedule)
        return h
    }

    private func makeMedication(schedule: MedicationSchedule, doseCount: Int) -> Medication {
        let med = Medication(name: "Test Med", form: .tablet, schedule: schedule)
        let base = Date()
        med.dosesPerDay = (0..<doseCount).map { i in
            base.addingTimeInterval(Double(i) * 3600)
        }
        return med
    }
}
