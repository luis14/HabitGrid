import Foundation

/// Defines when a habit is considered "due".
enum HabitSchedule: Codable, Hashable, Sendable {
    case daily
    case weekdays                  // Mon–Fri
    case customDays([Int])         // 0 = Sun … 6 = Sat (Calendar.weekday - 1)
    case timesPerWeek(Int)         // any N days in a calendar week

    // MARK: - Display

    var displayName: String {
        switch self {
        case .daily:
            return NSLocalizedString("Every Day", comment: "Habit schedule")
        case .weekdays:
            return NSLocalizedString("Weekdays", comment: "Habit schedule")
        case .customDays(let days):
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                .map { NSLocalizedString($0, comment: "Day abbreviation") }
            return days.sorted().compactMap { names[safe: $0] }.joined(separator: ", ")
        case .timesPerWeek(let n):
            return String(format: NSLocalizedString("%d× per week", comment: "Habit schedule"), n)
        }
    }

    var isWeekBased: Bool {
        if case .timesPerWeek = self { return true }
        return false
    }

    // MARK: - Scheduling

    /// Returns true if this habit is scheduled on `date` under `calendar`.
    func isDue(on date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .daily:
            return true
        case .weekdays:
            let weekday = calendar.component(.weekday, from: date)
            return weekday >= 2 && weekday <= 6
        case .customDays(let days):
            let weekday = calendar.component(.weekday, from: date) - 1 // 0-based
            return days.contains(weekday)
        case .timesPerWeek:
            return true // eligible every day; streak logic checks the whole week
        }
    }

    // MARK: - Codable (manual, to handle associated-value enums cleanly)

    private enum CodingKeys: String, CodingKey { case type, days, count }
    private enum TypeKey: String { case daily, weekdays, customDays, timesPerWeek }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily:
            try c.encode(TypeKey.daily.rawValue, forKey: .type)
        case .weekdays:
            try c.encode(TypeKey.weekdays.rawValue, forKey: .type)
        case .customDays(let days):
            try c.encode(TypeKey.customDays.rawValue, forKey: .type)
            try c.encode(days, forKey: .days)
        case .timesPerWeek(let n):
            try c.encode(TypeKey.timesPerWeek.rawValue, forKey: .type)
            try c.encode(n, forKey: .count)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch TypeKey(rawValue: type) {
        case .daily:      self = .daily
        case .weekdays:   self = .weekdays
        case .customDays: self = .customDays(try c.decode([Int].self, forKey: .days))
        case .timesPerWeek: self = .timesPerWeek(try c.decode(Int.self, forKey: .count))
        case .none:       self = .daily
        }
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
