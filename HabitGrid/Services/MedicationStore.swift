import Foundation
import SwiftData
import Observation

@Observable
final class MedicationStore {

    @ObservationIgnored private var context: ModelContext

    private(set) var activeMedications: [Medication] = []
    private(set) var archivedMedications: [Medication] = []

    init(context: ModelContext) {
        self.context = context
        try? refreshMedications()
    }

    // MARK: - CRUD

    func addMedication(_ medication: Medication) throws {
        medication.sortOrder = (activeMedications.last?.sortOrder ?? -1) + 1
        context.insert(medication)
        try save()
    }

    func updateMedication(_ medication: Medication) throws {
        try save()
    }

    func archiveMedication(_ medication: Medication) throws {
        medication.archivedAt = Date()
        try save()
    }

    func unarchiveMedication(_ medication: Medication) throws {
        medication.archivedAt = nil
        try save()
    }

    func deleteMedication(_ medication: Medication) throws {
        let medID = medication.id
        let descriptor = FetchDescriptor<MedicationDose>(
            predicate: #Predicate { $0.medicationID == medID }
        )
        let doses = (try? context.fetch(descriptor)) ?? []
        doses.forEach { context.delete($0) }
        context.delete(medication)
        try save()
    }

    func reorder(medications: [Medication]) throws {
        for (index, med) in medications.enumerated() {
            med.sortOrder = index
        }
        try save()
    }

    // MARK: - Dose generation

    /// Idempotently creates MedicationDose records for every scheduled date
    /// between medication.startDate and `through` (inclusive).
    /// asNeeded medications are skipped — user logs those manually.
    func materializeDoses(for medication: Medication, through endDate: Date) throws {
        if case .asNeeded = medication.schedule { return }
        try _materialize(medication: medication, through: endDate)
    }

    private static let maxMaterializeDays = 1095   // 3 years

    private func _materialize(medication: Medication, through endDate: Date) throws {
        let calendar = Calendar.current
        guard !medication.dosesPerDay.isEmpty else { return }

        let windowStart = medication.startDate
        let cap = medication.endDate.map { calendar.startOfDay(for: $0) }
              ?? calendar.startOfDay(for: endDate)
        // Cap to avoid runaway generation for medications with no end date
        let maxEnd = calendar.date(byAdding: .day, value: Self.maxMaterializeDays, to: windowStart) ?? endDate
        let windowEnd = min(cap, min(calendar.startOfDay(for: endDate), maxEnd))
        guard windowStart <= windowEnd else { return }

        // Fetch all existing doses in the window to enable O(1) duplicate checks
        let medID = medication.id
        var existing = FetchDescriptor<MedicationDose>(
            predicate: #Predicate { $0.medicationID == medID && $0.date >= windowStart && $0.date <= windowEnd }
        )
        existing.fetchLimit = 10_000
        let existingDoses = (try? context.fetch(existing)) ?? []
        let existingScheduledAts = Set(existingDoses.map(\.scheduledAt))

        var cursor = windowStart
        while cursor <= windowEnd {
            if medication.schedule.isDue(on: cursor, calendar: calendar) {
                for doseTime in medication.dosesPerDay {
                    let comps = calendar.dateComponents([.hour, .minute], from: doseTime)
                    let scheduledAt = calendar.date(
                        bySettingHour: comps.hour ?? 0,
                        minute: comps.minute ?? 0,
                        second: 0,
                        of: cursor
                    ) ?? cursor

                    if !existingScheduledAts.contains(scheduledAt) {
                        context.insert(MedicationDose(medicationID: medID, scheduledAt: scheduledAt))
                    }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        try context.save()
    }

    // MARK: - Dose actions

    func markTaken(_ dose: MedicationDose, at takenAt: Date = Date()) throws {
        let medID  = dose.medicationID
        let doseID = dose.id
        dose.takenAt = takenAt
        dose.status  = .taken
        decrementInventory(medicationID: medID)
        try context.save()
        Task { await NotificationService.shared.cancelFollowUps(medicationID: medID, doseID: doseID) }
    }

    func markSkipped(_ dose: MedicationDose) throws {
        let medID  = dose.medicationID
        let doseID = dose.id
        dose.status = .skipped
        try context.save()
        Task { await NotificationService.shared.cancelFollowUps(medicationID: medID, doseID: doseID) }
    }

    /// Resets a dose to pending so the user can correct a mistake.
    /// Re-increments inventory if the dose had been marked taken.
    func resetToPending(_ dose: MedicationDose) throws {
        let wasTaken    = dose.status == .taken
        let medID       = dose.medicationID
        dose.status     = .pending
        dose.takenAt    = nil
        if wasTaken {
            // Re-increment using a fresh fetch so we never touch a stale model reference
            let descriptor = FetchDescriptor<Medication>(predicate: #Predicate { $0.id == medID })
            if let med = try? context.fetch(descriptor).first, med.pillCount != nil {
                med.pillCount = (med.pillCount ?? 0) + max(1, med.pillsPerDose)
            }
        }
        try save()
    }

    /// Creates a taken dose record for a PRN (as-needed) medication.
    func logPRNDose(for medication: Medication, at date: Date = Date()) throws {
        let dose = MedicationDose(
            medicationID: medication.id,
            scheduledAt: date,
            takenAt: date,
            status: .taken
        )
        context.insert(dose)
        decrementInventory(medicationID: medication.id)
        try save()
    }

    private func decrementInventory(medicationID: UUID) {
        let descriptor = FetchDescriptor<Medication>(predicate: #Predicate { $0.id == medicationID })
        guard let med = (try? context.fetch(descriptor))?.first,
              med.pillCount != nil else { return }
        let perDose  = max(1, med.pillsPerDose)
        let newCount = max(0, (med.pillCount ?? 0) - perDose)
        med.pillCount = newCount
        if newCount <= med.lowStockThreshold {
            let name = med.name
            let form = med.form.displayName.lowercased()
            let id   = med.id
            Task { @MainActor in
                await NotificationService.shared.sendLowStockAlert(
                    name: name, formDisplay: form, count: newCount, medicationID: id
                )
            }
        }
    }

    /// Marks every pending dose whose scheduledAt is before `cutoff` as missed.
    func sweepMissed(asOf cutoff: Date = Date()) throws {
        var descriptor = FetchDescriptor<MedicationDose>(
            predicate: #Predicate { $0.statusRaw == "pending" && $0.scheduledAt < cutoff }
        )
        descriptor.fetchLimit = 10_000
        let overdue = (try? context.fetch(descriptor)) ?? []
        for dose in overdue { dose.status = .missed }
        if !overdue.isEmpty { try context.save() }
    }

    // MARK: - Queries

    func doses(for medication: Medication, from startDate: Date, to endDate: Date) throws -> [MedicationDose] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end   = Calendar.current.startOfDay(for: endDate)
        let medID = medication.id
        var descriptor = FetchDescriptor<MedicationDose>(
            predicate: #Predicate { $0.medicationID == medID && $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.scheduledAt)]
        )
        descriptor.fetchLimit = 5_000
        return try context.fetch(descriptor)
    }

    /// All doses for any medication on `date` (all statuses).
    func doses(on date: Date) throws -> [MedicationDose] {
        let day = Calendar.current.startOfDay(for: date)
        var descriptor = FetchDescriptor<MedicationDose>(
            predicate: #Predicate { $0.date == day },
            sortBy: [SortDescriptor(\.scheduledAt)]
        )
        descriptor.fetchLimit = 500
        return try context.fetch(descriptor)
    }

    /// All pending doses whose date equals the start of `date`.
    func dosesDue(on date: Date) throws -> [MedicationDose] {
        let day = Calendar.current.startOfDay(for: date)
        var descriptor = FetchDescriptor<MedicationDose>(
            predicate: #Predicate { $0.date == day && $0.statusRaw == "pending" },
            sortBy: [SortDescriptor(\.scheduledAt)]
        )
        descriptor.fetchLimit = 500
        return try context.fetch(descriptor)
    }

    /// Fraction of non-pending doses that were taken, over the last `days` days.
    func adherenceRate(for medication: Medication, days: Int) throws -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return 0 }
        let all = try doses(for: medication, from: start, to: today)
        let resolved = all.filter { $0.status != .pending }
        guard !resolved.isEmpty else { return 0 }
        let taken = resolved.filter { $0.status == .taken }.count
        return Double(taken) / Double(resolved.count)
    }

    // MARK: - Intensity

    /// 0–4 intensity bucket for the contribution graph: taken/total for `date`.
    func intensity(for medication: Medication, on date: Date) throws -> Int {
        let dayDoses = try doses(for: medication, from: date, to: date)
        guard !dayDoses.isEmpty else { return 0 }
        let taken = dayDoses.filter { $0.status == .taken }.count
        return Self.intensityBucket(taken: taken, total: dayDoses.count)
    }

    /// Combined intensity across all active medications on `date`.
    func overallIntensity(on date: Date) throws -> Int {
        let day = Calendar.current.startOfDay(for: date)
        var descriptor = FetchDescriptor<MedicationDose>(
            predicate: #Predicate { $0.date == day }
        )
        descriptor.fetchLimit = 500
        let dayDoses = (try? context.fetch(descriptor)) ?? []
        guard !dayDoses.isEmpty else { return 0 }
        let taken = dayDoses.filter { $0.status == .taken }.count
        return Self.intensityBucket(taken: taken, total: dayDoses.count)
    }

    /// Pure function — 0 none, 1–3 partial, 4 full adherence.
    static func intensityBucket(taken: Int, total: Int) -> Int {
        guard total > 0, taken > 0 else { return 0 }
        let ratio = Double(taken) / Double(total)
        switch ratio {
        case ..<0.25:    return 1
        case 0.25..<0.5: return 2
        case 0.5..<0.75: return 3
        default:          return 4
        }
    }

    // MARK: - Adherence streak

    /// Consecutive days (walking backward from today) on which all scheduled
    /// doses were taken. Today is given a grace period if all doses are still pending.
    func currentAdherenceStreak(for medication: Medication) throws -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var checkDate = today

        let todayDoses = try doses(for: medication, from: today, to: today)
        if !todayDoses.isEmpty && todayDoses.allSatisfy({ $0.status == .pending }) {
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { return 0 }
            checkDate = prev
        }

        var streak = 0
        while checkDate >= medication.startDate {
            if medication.schedule.isDue(on: checkDate, calendar: calendar) {
                let dayDoses = try doses(for: medication, from: checkDate, to: checkDate)
                if dayDoses.isEmpty {
                    // Not materialized — skip without breaking
                } else if dayDoses.allSatisfy({ $0.status == .taken }) {
                    streak += 1
                } else if dayDoses.allSatisfy({ $0.status == .pending }) {
                    // In-progress (shouldn't occur for past days after sweep) — skip
                } else {
                    break
                }
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }
        return streak
    }

    func longestAdherenceStreak(for medication: Medication) throws -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var longest = 0
        var current = 0
        var cursor = medication.startDate

        while cursor <= today {
            if medication.schedule.isDue(on: cursor, calendar: calendar) {
                let dayDoses = try doses(for: medication, from: cursor, to: cursor)
                if !dayDoses.isEmpty && dayDoses.allSatisfy({ $0.status == .taken }) {
                    current += 1
                    longest = max(longest, current)
                } else if !dayDoses.isEmpty {
                    current = 0
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return longest
    }

    // MARK: - Public refresh

    func refresh() {
        try? refreshMedications()
    }

    // MARK: - Private

    private func refreshMedications() throws {
        var active = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        active.fetchLimit = 200
        activeMedications = try context.fetch(active)

        var archived = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.archivedAt != nil },
            sortBy: [SortDescriptor(\.archivedAt, order: .reverse)]
        )
        archived.fetchLimit = 200
        archivedMedications = try context.fetch(archived)
    }

    private func save() throws {
        try context.save()
        try refreshMedications()
    }
}
