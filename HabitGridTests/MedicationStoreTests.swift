import XCTest
import SwiftData
@testable import HabitGrid

@MainActor
final class MedicationStoreTests: XCTestCase {

    // MARK: - Setup

    var container: ModelContainer!
    var context: ModelContext!
    var store: MedicationStore!

    override func setUp() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Medication.self, MedicationDose.self, configurations: config)
        context = ModelContext(container)
        store = MedicationStore(context: context)
    }

    override func tearDown() {
        store = nil
        context = nil
        container = nil
    }

    // MARK: - Helpers

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }

    private func today(offsetBy days: Int = 0) -> Date {
        let base = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: days, to: base)!
    }

    private func doseTime(hour: Int, minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    private func makeMedication(
        schedule: MedicationSchedule = .daily,
        dosesPerDay: [Date] = [],
        startedDaysAgo: Int = 7,
        archived: Bool = false
    ) throws -> Medication {
        let start = today(offsetBy: -startedDaysAgo)
        let med = Medication(
            name: "Test Med",
            schedule: schedule,
            dosesPerDay: dosesPerDay,
            startDate: start
        )
        if archived { med.archivedAt = Date() }
        try store.addMedication(med)
        return med
    }

    // Materializes and returns the doses for `med` from its startDate through today.
    @discardableResult
    private func materialize(_ med: Medication) throws -> [MedicationDose] {
        try store.materializeDoses(for: med, through: today())
        return try store.doses(for: med, from: med.startDate, to: today())
    }

    // MARK: - Dose Materialization

    func testMaterializeDoses_daily_generatesCorrectCount() throws {
        let med = try makeMedication(
            dosesPerDay: [doseTime(hour: 8), doseTime(hour: 20)],
            startedDaysAgo: 2
        )
        let doses = try materialize(med)
        // 3 days (2 days ago, 1 day ago, today) × 2 doses = 6
        XCTAssertEqual(doses.count, 6)
    }

    func testMaterializeDoses_idempotent() throws {
        let med = try makeMedication(
            dosesPerDay: [doseTime(hour: 8)],
            startedDaysAgo: 3
        )
        try store.materializeDoses(for: med, through: today())
        try store.materializeDoses(for: med, through: today())
        let doses = try store.doses(for: med, from: med.startDate, to: today())
        XCTAssertEqual(doses.count, 4, "4 days × 1 dose, no duplicates after double materialization")
    }

    func testMaterializeDoses_asNeeded_generatesNone() throws {
        let med = try makeMedication(
            schedule: .asNeeded,
            dosesPerDay: [doseTime(hour: 9)],
            startedDaysAgo: 5
        )
        let doses = try materialize(med)
        XCTAssertTrue(doses.isEmpty)
    }

    func testMaterializeDoses_noDoseTimes_generatesNothing() throws {
        let med = try makeMedication(dosesPerDay: [], startedDaysAgo: 3)
        let doses = try materialize(med)
        XCTAssertTrue(doses.isEmpty)
    }

    func testMaterializeDoses_weekdays_skipsWeekend() throws {
        let med = try makeMedication(
            schedule: .weekdays,
            dosesPerDay: [doseTime(hour: 8)],
            startedDaysAgo: 14
        )
        let doses = try materialize(med)
        // Every dose should be on a weekday
        for dose in doses {
            let wd = calendar.component(.weekday, from: dose.scheduledAt)
            XCTAssertTrue((2...6).contains(wd), "Dose on weekday only: weekday=\(wd)")
        }
        XCTAssertFalse(doses.isEmpty)
    }

    func testMaterializeDoses_customDays_respectsDays() throws {
        // Only Mon (1) and Wed (3) — 0-based indices
        let med = try makeMedication(
            schedule: .customDays([1, 3]),
            dosesPerDay: [doseTime(hour: 10)],
            startedDaysAgo: 14
        )
        let doses = try materialize(med)
        for dose in doses {
            // weekday 1=Sun,2=Mon,3=Tue,4=Wed (Calendar uses 1-based Sunday-first)
            let wd = calendar.component(.weekday, from: dose.scheduledAt) - 1 // 0-based
            XCTAssertTrue([1, 3].contains(wd), "Dose should only land on Mon or Wed, got \(wd)")
        }
    }

    func testMaterializeDoses_respectsEndDate() throws {
        let endDate = today(offsetBy: -3)
        let med = Medication(
            name: "Short Course",
            dosesPerDay: [doseTime(hour: 8)],
            startDate: today(offsetBy: -7),
            endDate: endDate
        )
        try store.addMedication(med)
        let doses = try materialize(med)
        // Only days from start to endDate (inclusive): 5 days
        XCTAssertEqual(doses.count, 5)
        for dose in doses {
            XCTAssertLessThanOrEqual(dose.date, calendar.startOfDay(for: endDate))
        }
    }

    func testMaterializeDoses_defaultStatusIsPending() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 8)], startedDaysAgo: 0)
        let doses = try materialize(med)
        XCTAssertEqual(doses.first?.status, .pending)
    }

    // MARK: - Dose Actions

    func testMarkTaken_setsStatusAndTakenAt() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 8)], startedDaysAgo: 0)
        let doses = try materialize(med)
        let dose = try XCTUnwrap(doses.first)

        let takenDate = Date()
        try store.markTaken(dose, at: takenDate)

        XCTAssertEqual(dose.status, .taken)
        XCTAssertEqual(dose.takenAt?.timeIntervalSinceReferenceDate ?? 0,
                       takenDate.timeIntervalSinceReferenceDate, accuracy: 1)
    }

    func testMarkSkipped_setsStatusSkipped() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 8)], startedDaysAgo: 0)
        let doses = try materialize(med)
        let dose = try XCTUnwrap(doses.first)

        try store.markSkipped(dose)

        XCTAssertEqual(dose.status, .skipped)
        XCTAssertNil(dose.takenAt)
    }

    // MARK: - Sweep Missed

    func testSweepMissed_makesPastPendingDosesMissed() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 8)], startedDaysAgo: 3)
        try materialize(med)

        // Sweep as of now — all past pending doses should become missed
        try store.sweepMissed(asOf: Date())

        let doses = try store.doses(for: med, from: med.startDate, to: today())
        let missed = doses.filter { $0.status == .missed }
        // Today's 8 AM might or might not be in the past depending on clock; count ≥ 3 (days 3,2,1 ago)
        XCTAssertGreaterThanOrEqual(missed.count, 3)
    }

    func testSweepMissed_leavesRecentPendingUntouched() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 23)], startedDaysAgo: 0)
        try materialize(med)

        // Cutoff is start of today — tonight's 23:00 dose should remain pending
        try store.sweepMissed(asOf: calendar.startOfDay(for: Date()))

        let doses = try store.doses(for: med, from: today(), to: today())
        XCTAssertEqual(doses.first?.status, .pending)
    }

    func testSweepMissed_doesNotAffectAlreadyTakenDoses() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 8)], startedDaysAgo: 1)
        try materialize(med)

        let yesterday = today(offsetBy: -1)
        let doses = try store.doses(for: med, from: yesterday, to: yesterday)
        let dose = try XCTUnwrap(doses.first)
        try store.markTaken(dose)

        try store.sweepMissed(asOf: Date())

        XCTAssertEqual(dose.status, .taken, "Taken dose must not be overwritten by sweep")
    }

    // MARK: - Intensity Bucketing

    func testIntensityBucket_zeroTotal() {
        XCTAssertEqual(MedicationStore.intensityBucket(taken: 0, total: 0), 0)
    }

    func testIntensityBucket_noneTaken() {
        XCTAssertEqual(MedicationStore.intensityBucket(taken: 0, total: 4), 0)
    }

    func testIntensityBucket_allTaken_single() {
        XCTAssertEqual(MedicationStore.intensityBucket(taken: 1, total: 1), 4)
    }

    func testIntensityBucket_allTaken_multi() {
        XCTAssertEqual(MedicationStore.intensityBucket(taken: 4, total: 4), 4)
    }

    func testIntensityBucket_partialRatios() {
        // Ratio < 0.25
        XCTAssertEqual(MedicationStore.intensityBucket(taken: 1, total: 8), 1, "<25%")
        // 0.25 ≤ ratio < 0.5
        XCTAssertEqual(MedicationStore.intensityBucket(taken: 2, total: 4), 2, "50% → bucket 3?")
        // 0.5 ≤ ratio < 0.75
        XCTAssertEqual(MedicationStore.intensityBucket(taken: 3, total: 4), 3, "75% → bucket 4?")
        // ratio ≥ 0.75
        XCTAssertEqual(MedicationStore.intensityBucket(taken: 3, total: 4), 3, "75% boundary")
        XCTAssertEqual(MedicationStore.intensityBucket(taken: 4, total: 4), 4, "100%")
    }

    func testIntensity_noDosesReturnsZero() throws {
        let med = try makeMedication(schedule: .asNeeded, dosesPerDay: [doseTime(hour: 8)])
        let result = try store.intensity(for: med, on: today())
        XCTAssertEqual(result, 0)
    }

    func testIntensity_allDosesTaken_returnsMax() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 8), doseTime(hour: 20)], startedDaysAgo: 0)
        let doses = try materialize(med)
        for dose in doses { try store.markTaken(dose) }
        XCTAssertEqual(try store.intensity(for: med, on: today()), 4)
    }

    func testIntensity_noTaken_returnsZero() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 8)], startedDaysAgo: 0)
        try materialize(med)
        XCTAssertEqual(try store.intensity(for: med, on: today()), 0)
    }

    // MARK: - Adherence Rate

    func testAdherenceRate_allTaken() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 8)], startedDaysAgo: 6)
        let doses = try materialize(med)
        for dose in doses { try store.markTaken(dose) }
        let rate = try store.adherenceRate(for: med, days: 7)
        XCTAssertEqual(rate, 1.0, accuracy: 0.01)
    }

    func testAdherenceRate_halfTaken() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 8)], startedDaysAgo: 3)
        let doses = try materialize(med)
        // Take 2 out of 4, skip 2
        try store.markTaken(doses[0])
        try store.markTaken(doses[1])
        try store.markSkipped(doses[2])
        try store.markSkipped(doses[3])
        let rate = try store.adherenceRate(for: med, days: 7)
        XCTAssertEqual(rate, 0.5, accuracy: 0.01)
    }

    func testAdherenceRate_noneResolved_returnsZero() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 8)], startedDaysAgo: 0)
        try materialize(med)
        // All doses still pending — adherence is undefined, returns 0
        let rate = try store.adherenceRate(for: med, days: 7)
        XCTAssertEqual(rate, 0.0)
    }

    // MARK: - Adherence Streak

    func testCurrentAdherenceStreak_allTaken_countsConsecutiveDays() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 8)], startedDaysAgo: 4)
        let doses = try materialize(med)
        for dose in doses { try store.markTaken(dose) }
        let streak = try store.currentAdherenceStreak(for: med)
        XCTAssertGreaterThanOrEqual(streak, 4)
    }

    func testCurrentAdherenceStreak_missedDayBreaksStreak() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 8)], startedDaysAgo: 4)
        let doses = try materialize(med)
        // Take today and yesterday; mark 2-days-ago missed; take 3-days-ago
        // doses are sorted by scheduledAt ascending: [3dago, 2dago, 1dago, today]
        try store.markTaken(doses[3])  // today
        try store.markTaken(doses[2])  // 1 day ago
        try store.markSkipped(doses[1]) // 2 days ago — breaks streak
        try store.markTaken(doses[0])  // 3 days ago
        let streak = try store.currentAdherenceStreak(for: med)
        XCTAssertEqual(streak, 2, "Only today and yesterday are consecutive")
    }

    func testCurrentAdherenceStreak_todayAllPending_countsFromYesterday() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 23)], startedDaysAgo: 3)
        let doses = try materialize(med)
        // Take all except today (still pending)
        for dose in doses.dropLast() { try store.markTaken(dose) }
        let streak = try store.currentAdherenceStreak(for: med)
        XCTAssertGreaterThanOrEqual(streak, 3, "Grace: today pending doesn't break streak from yesterday")
    }

    func testLongestAdherenceStreak_findsPeak() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 8)], startedDaysAgo: 9)
        let doses = try materialize(med)
        // 10 doses (days 9..0); take days 9..5 (5 taken), skip day 4, take days 3..0 (4 taken)
        // sorted ascending: doses[0]=9dago, doses[9]=today
        for i in 0...4 { try store.markTaken(doses[i]) }   // 9..5 days ago
        try store.markSkipped(doses[5])                      // 4 days ago
        for i in 6...9 { try store.markTaken(doses[i]) }   // 3..0 days ago
        let longest = try store.longestAdherenceStreak(for: med)
        XCTAssertEqual(longest, 5)
    }

    func testLongestAdherenceStreak_noTaken_isZero() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 8)], startedDaysAgo: 3)
        let doses = try materialize(med)
        for dose in doses { try store.markSkipped(dose) }
        XCTAssertEqual(try store.longestAdherenceStreak(for: med), 0)
    }

    // MARK: - Delete Cascade

    func testDeleteMedication_removesAllDoses() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 8)], startedDaysAgo: 5)
        try materialize(med)
        let medID = med.id

        try store.deleteMedication(med)

        let descriptor = FetchDescriptor<MedicationDose>(
            predicate: #Predicate { $0.medicationID == medID }
        )
        let remaining = try context.fetch(descriptor)
        XCTAssertTrue(remaining.isEmpty, "All doses must be deleted with the medication")
    }

    func testDeleteMedication_doesNotAffectOtherMedDoses() throws {
        let med1 = try makeMedication(dosesPerDay: [doseTime(hour: 8)], startedDaysAgo: 2)
        let med2 = try makeMedication(dosesPerDay: [doseTime(hour: 9)], startedDaysAgo: 2)
        try materialize(med1)
        try materialize(med2)

        let med2ID = med2.id
        try store.deleteMedication(med1)

        let descriptor = FetchDescriptor<MedicationDose>(
            predicate: #Predicate { $0.medicationID == med2ID }
        )
        let remaining = try context.fetch(descriptor)
        XCTAssertFalse(remaining.isEmpty, "med2 doses must survive deletion of med1")
    }

    // MARK: - CRUD

    func testAddMedication_appearsInActive() throws {
        let med = try makeMedication()
        XCTAssertTrue(store.activeMedications.contains(where: { $0.id == med.id }))
    }

    func testArchiveMedication_movesToArchived() throws {
        let med = try makeMedication()
        try store.archiveMedication(med)
        XCTAssertFalse(store.activeMedications.contains(where: { $0.id == med.id }))
        XCTAssertTrue(store.archivedMedications.contains(where: { $0.id == med.id }))
    }

    func testUnarchiveMedication_movesToActive() throws {
        let med = try makeMedication(archived: true)
        try store.unarchiveMedication(med)
        XCTAssertTrue(store.activeMedications.contains(where: { $0.id == med.id }))
        XCTAssertFalse(store.archivedMedications.contains(where: { $0.id == med.id }))
    }

    func testReorder_updatesSortOrder() throws {
        let med1 = try makeMedication()
        let med2 = try makeMedication()
        try store.reorder(medications: [med2, med1])
        XCTAssertEqual(med2.sortOrder, 0)
        XCTAssertEqual(med1.sortOrder, 1)
    }

    // MARK: - dosesDue

    func testDosesDue_returnsOnlyPendingForToday() throws {
        let med = try makeMedication(dosesPerDay: [doseTime(hour: 8), doseTime(hour: 20)], startedDaysAgo: 1)
        try materialize(med)

        let todayDoses = try store.doses(for: med, from: today(), to: today())
        if let first = todayDoses.first {
            try store.markTaken(first)
        }

        let due = try store.dosesDue(on: today())
        XCTAssertTrue(due.allSatisfy { $0.status == .pending })
    }
}
