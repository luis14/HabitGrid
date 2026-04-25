import Foundation
import UserNotifications

/// Schedules and cancels local notifications for habit and medication reminders.
///
/// iOS caps pending notifications at 64. This service reserves 60 slots
/// (leaving 4 as system buffer), prioritising medications over habits.
/// When a habit's reminder would push the count over 60 the request is
/// dropped and the name is reported to `NotificationCapBannerState`.
actor NotificationService {

    static let shared = NotificationService()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    // MARK: - Budget

    /// Maximum pending notification requests this app will create.
    static let notificationBudget = 60

    /// Number of pending requests a habit would consume.
    static func requestCount(for habit: Habit) -> Int {
        switch habit.schedule {
        case .daily, .timesPerWeek: return 1
        case .weekdays:             return 5
        case .customDays(let d):    return d.count
        }
    }

    /// Number of pending requests a medication would consume (one per dose-time × weekday combo).
    static func requestCount(for medication: Medication) -> Int {
        let doseCount = max(1, medication.dosesPerDay.count)
        switch medication.schedule {
        case .daily:            return doseCount
        case .weekdays:         return doseCount * 5
        case .customDays(let d):return doseCount * d.count
        case .asNeeded:         return 0
        }
    }

    /// Pure function — `true` when adding `newSlots` to `pending` would exceed the budget.
    static func wouldExceedBudget(pending: Int, newSlots: Int) -> Bool {
        pending + newSlots > notificationBudget
    }

    // MARK: - Permission

    /// Returns `true` if permission was granted (or was already granted).
    @discardableResult
    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    var isAuthorised: Bool {
        get async {
            await center.notificationSettings().authorizationStatus == .authorized
        }
    }

    // MARK: - Schedule

    /// Schedules notification(s) for `habit`. Replaces any existing requests.
    /// Skips scheduling and reports to `NotificationCapBannerState` when the
    /// 60-request budget would be exceeded.
    func schedule(for habit: Habit) async {
        guard let reminderTime = habit.reminderTime, !habit.isArchived else {
            cancel(for: habit)
            return
        }
        guard await isAuthorised else { return }

        cancel(for: habit)   // remove stale requests first (lowers pending count)

        let slotsNeeded = Self.requestCount(for: habit)
        let currentPending = await center.pendingNotificationRequests().count
        if Self.wouldExceedBudget(pending: currentPending, newSlots: slotsNeeded) {
            let name = habit.name
            await MainActor.run {
                NotificationCapBannerState.shared.report(droppedNames: [name])
            }
            return
        }

        let cal = Calendar.current
        let hourMinute = cal.dateComponents([.hour, .minute], from: reminderTime)

        let content = UNMutableNotificationContent()
        content.title = "\(habit.emoji) \(habit.name)"
        content.body  = "Time to check in on your habit."
        content.sound = .default

        switch habit.schedule {
        case .daily, .timesPerWeek:
            await add(id: notifID(habit), content: content, components: hourMinute)

        case .weekdays:
            for wd in 2...6 {
                var comps = hourMinute
                comps.weekday = wd
                await add(id: notifID(habit, suffix: wd), content: content, components: comps)
            }

        case .customDays(let days):
            for day in days {
                var comps = hourMinute
                comps.weekday = day + 1
                await add(id: notifID(habit, suffix: day), content: content, components: comps)
            }
        }
    }

    /// Cancels all notifications for `habit`.
    func cancel(for habit: Habit) {
        let ids = pendingIDs(for: habit)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Re-schedules reminders for all non-archived habits.
    /// Medications are scheduled first (higher priority); habits fill the remaining budget.
    func rescheduleAll(habits: [Habit]) async {
        for habit in habits { await schedule(for: habit) }
    }

    /// Combined reschedule that enforces priority: medications consume budget first,
    /// habits fill whatever is left. Dropped names are reported as a single banner.
    func rescheduleAll(habits: [Habit], medications: [Medication]) async {
        guard await isAuthorised else { return }

        // Cancel everything to get an accurate pending count.
        for habit in habits { cancel(for: habit) }
        for med in medications { cancel(for: med) }

        var pending = await center.pendingNotificationRequests().count
        var dropped: [String] = []

        // Medications first.
        for med in medications {
            let slots = Self.requestCount(for: med)
            if Self.wouldExceedBudget(pending: pending, newSlots: slots) {
                dropped.append(med.name)
            } else {
                await scheduleNoCapCheck(for: med)
                pending += slots
            }
        }

        // Habits second.
        for habit in habits {
            guard habit.reminderTime != nil, !habit.isArchived else { continue }
            let slots = Self.requestCount(for: habit)
            if Self.wouldExceedBudget(pending: pending, newSlots: slots) {
                dropped.append(habit.name)
            } else {
                await scheduleNoCapCheck(for: habit)
                pending += slots
            }
        }

        if !dropped.isEmpty {
            let droppedCopy = dropped
            await MainActor.run {
                NotificationCapBannerState.shared.report(droppedNames: droppedCopy)
            }
        }
    }

    // MARK: - Medication notifications

    /// Schedules a repeating daily/weekly reminder at each dose time.
    /// Follow-up reminders (+15, +30 min) are one-shot triggers tied to a
    /// specific MedicationDose — call `scheduleFollowUps(for:medication:)` separately.
    func schedule(for medication: Medication) async {
        cancel(for: medication)
        guard !medication.isArchived else { return }
        guard await isAuthorised else { return }
        if case .asNeeded = medication.schedule { return }
        guard !medication.dosesPerDay.isEmpty else { return }

        let cal = Calendar.current
        let desc = medication.strength.isEmpty
            ? medication.form.displayName.lowercased()
            : "\(medication.strength) \(medication.form.displayName.lowercased())"

        for (i, doseTime) in medication.dosesPerDay.enumerated() {
            let hm = cal.dateComponents([.hour, .minute], from: doseTime)

            let content = UNMutableNotificationContent()
            content.title = medication.name
            content.body  = "Time to take your \(desc)."
            content.sound = .default
            if #available(iOS 15.0, *) {
                content.interruptionLevel = .timeSensitive
            }

            switch medication.schedule {
            case .daily:
                await add(id: medID(medication, dose: i, slot: 0),
                          content: content, components: hm)
            case .weekdays:
                for wd in 2...6 {
                    var c = hm; c.weekday = wd
                    await add(id: medID(medication, dose: i, slot: 0, suffix: wd),
                              content: content, components: c)
                }
            case .customDays(let days):
                for day in days {
                    var c = hm; c.weekday = day + 1
                    await add(id: medID(medication, dose: i, slot: 0, suffix: day),
                              content: content, components: c)
                }
            case .asNeeded:
                break
            }
        }
    }

    /// Follow-up offsets: every 15 min for up to 2 hours after the scheduled dose time.
    private static let followUpOffsets = stride(from: 15, through: 120, by: 15).map { $0 }

    /// Schedules one-shot follow-up reminders every 15 min (up to 2 hours) for a pending dose.
    /// Only schedules triggers that are still in the future. Call on app launch for every
    /// pending dose so reminders continue even after the app was backgrounded.
    func scheduleFollowUps(for dose: MedicationDose, medication: Medication) async {
        guard await isAuthorised, dose.status == .pending else { return }
        let now = Date()
        let desc = medication.strength.isEmpty
            ? medication.form.displayName.lowercased()
            : "\(medication.strength) \(medication.form.displayName.lowercased())"

        for offsetMin in Self.followUpOffsets {
            let fireDate = dose.scheduledAt.addingTimeInterval(Double(offsetMin) * 60)
            guard fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = medication.name
            content.body  = "Reminder: still time to take your \(desc)."
            content.sound = .default
            if #available(iOS 15.0, *) {
                content.interruptionLevel = .timeSensitive
            }

            let interval = fireDate.timeIntervalSinceNow
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
            let id = followUpID(dose: dose, offsetMin: offsetMin)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// Cancels all pending follow-up reminders for a dose (call when dose is taken or skipped).
    func cancelFollowUps(for dose: MedicationDose) {
        let ids = Self.followUpOffsets.map { followUpID(dose: dose, offsetMin: $0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Primitive-based overload — safe to call after `context.save()` when the model
    /// backing may have been invalidated.
    func cancelFollowUps(medicationID: UUID, doseID: UUID) {
        let ids = Self.followUpOffsets.map { "med-followup-\(medicationID)-\(doseID)-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Cancels all notifications for a medication.
    func cancel(for medication: Medication) {
        center.removePendingNotificationRequests(withIdentifiers: allMedIDs(for: medication))
    }

    /// Cancels all notifications using raw primitives — safe to call after the
    /// SwiftData model has been deleted (backing data may already be cleared).
    func cancelMedication(id: UUID, doseCount: Int) {
        let ids = (0..<max(1, doseCount)).flatMap { d -> [String] in
            ["med-\(id)-d\(d)-s0"] + (0...6).map { "med-\(id)-d\(d)-s0-\($0)" }
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Re-schedules dose reminders for all active medications.
    func rescheduleAll(medications: [Medication]) async {
        for med in medications { await schedule(for: med) }
    }

    /// Fires an immediate low-stock alert. Uses primitives so it is safe to call
    /// after a model context save (avoids SwiftData backing-data invalidation).
    func sendLowStockAlert(name: String, formDisplay: String, count: Int, medicationID: UUID) async {
        guard await isAuthorised else { return }
        let content = UNMutableNotificationContent()
        content.title = "Low Supply: \(name)"
        content.body  = count == 0
            ? "You're out of \(formDisplay)s. Time to refill."
            : "Only \(count) \(formDisplay)\(count == 1 ? "" : "s") left. Time to refill."
        content.sound = .default
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        let id = "med-lowstock-\(medicationID)-\(Int(Date().timeIntervalSince1970))"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    // MARK: - Private (no-cap-check scheduling)

    /// Schedules notifications for a habit without re-checking the budget.
    /// Only call from `rescheduleAll(habits:medications:)` which tracks budget itself.
    private func scheduleNoCapCheck(for habit: Habit) async {
        guard let reminderTime = habit.reminderTime, !habit.isArchived else { return }

        let cal = Calendar.current
        let hourMinute = cal.dateComponents([.hour, .minute], from: reminderTime)

        let content = UNMutableNotificationContent()
        content.title = "\(habit.emoji) \(habit.name)"
        content.body  = "Time to check in on your habit."
        content.sound = .default

        switch habit.schedule {
        case .daily, .timesPerWeek:
            await add(id: notifID(habit), content: content, components: hourMinute)

        case .weekdays:
            for wd in 2...6 {
                var comps = hourMinute
                comps.weekday = wd
                await add(id: notifID(habit, suffix: wd), content: content, components: comps)
            }

        case .customDays(let days):
            for day in days {
                var comps = hourMinute
                comps.weekday = day + 1
                await add(id: notifID(habit, suffix: day), content: content, components: comps)
            }
        }
    }

    /// Schedules notifications for a medication without re-checking the budget.
    /// Only call from `rescheduleAll(habits:medications:)` which tracks budget itself.
    private func scheduleNoCapCheck(for medication: Medication) async {
        guard !medication.isArchived else { return }
        if case .asNeeded = medication.schedule { return }
        guard !medication.dosesPerDay.isEmpty else { return }

        let cal = Calendar.current
        let desc = medication.strength.isEmpty
            ? medication.form.displayName.lowercased()
            : "\(medication.strength) \(medication.form.displayName.lowercased())"

        for (i, doseTime) in medication.dosesPerDay.enumerated() {
            let hm = cal.dateComponents([.hour, .minute], from: doseTime)

            let content = UNMutableNotificationContent()
            content.title = medication.name
            content.body  = "Time to take your \(desc)."
            content.sound = .default
            if #available(iOS 15.0, *) {
                content.interruptionLevel = .timeSensitive
            }

            switch medication.schedule {
            case .daily:
                await add(id: medID(medication, dose: i, slot: 0),
                          content: content, components: hm)
            case .weekdays:
                for wd in 2...6 {
                    var c = hm; c.weekday = wd
                    await add(id: medID(medication, dose: i, slot: 0, suffix: wd),
                              content: content, components: c)
                }
            case .customDays(let days):
                for day in days {
                    var c = hm; c.weekday = day + 1
                    await add(id: medID(medication, dose: i, slot: 0, suffix: day),
                              content: content, components: c)
                }
            case .asNeeded:
                break
            }
        }
    }

    // MARK: - Private

    private func add(
        id: String,
        content: UNNotificationContent,
        components: DateComponents
    ) async {
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func notifID(_ habit: Habit, suffix: Int? = nil) -> String {
        suffix.map { "habit-\(habit.id)-\($0)" } ?? "habit-\(habit.id)"
    }

    private func pendingIDs(for habit: Habit) -> [String] {
        [notifID(habit)] + (0...6).map { notifID(habit, suffix: $0) }
    }

    private func medID(_ med: Medication, dose: Int, slot: Int = 0, suffix: Int? = nil) -> String {
        suffix.map { "med-\(med.id)-d\(dose)-s\(slot)-\($0)" } ?? "med-\(med.id)-d\(dose)-s\(slot)"
    }

    private func allMedIDs(for med: Medication) -> [String] {
        let doseCount = max(1, med.dosesPerDay.count)
        return (0..<doseCount).flatMap { d in
            [medID(med, dose: d, slot: 0)] + (0...6).map { medID(med, dose: d, slot: 0, suffix: $0) }
        }
    }

    private func followUpID(dose: MedicationDose, offsetMin: Int) -> String {
        "med-followup-\(dose.medicationID)-\(dose.id)-\(offsetMin)"
    }
}
