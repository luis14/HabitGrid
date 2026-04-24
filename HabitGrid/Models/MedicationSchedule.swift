import Foundation

// MARK: - MedicationSchedule

/// Defines when a medication dose is scheduled.
/// Mirrors HabitSchedule's Codable pattern; asNeeded is PRN (no fixed schedule).
enum MedicationSchedule: Codable, Hashable, Sendable {
    case daily
    case weekdays                // Mon–Fri
    case customDays([Int])       // 0 = Sun … 6 = Sat
    case asNeeded                // PRN — user logs when taken, no generated doses

    // MARK: - Display

    var displayName: String {
        switch self {
        case .daily:
            return NSLocalizedString("Every Day", comment: "Medication schedule")
        case .weekdays:
            return NSLocalizedString("Weekdays (Mon–Fri)", comment: "Medication schedule")
        case .customDays(let days):
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                .map { NSLocalizedString($0, comment: "Day abbreviation") }
            return days.sorted().compactMap { names[safe: $0] }.joined(separator: ", ")
        case .asNeeded:
            return NSLocalizedString("As Needed (PRN)", comment: "Medication schedule")
        }
    }

    /// Returns true when the medication is scheduled on `date`.
    /// asNeeded always returns false — no automatic dose generation.
    func isDue(on date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .daily:
            return true
        case .weekdays:
            let wd = calendar.component(.weekday, from: date)
            return wd >= 2 && wd <= 6
        case .customDays(let days):
            let wd = calendar.component(.weekday, from: date) - 1  // 0-based
            return days.contains(wd)
        case .asNeeded:
            return false
        }
    }

    // MARK: - Codable (manual, to handle associated-value enums cleanly)

    private enum CodingKeys: String, CodingKey { case type, days }
    private enum TypeKey: String { case daily, weekdays, customDays, asNeeded }

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
        case .asNeeded:
            try c.encode(TypeKey.asNeeded.rawValue, forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch TypeKey(rawValue: type) {
        case .daily:      self = .daily
        case .weekdays:   self = .weekdays
        case .customDays: self = .customDays(try c.decode([Int].self, forKey: .days))
        case .asNeeded:   self = .asNeeded
        case .none:       self = .daily
        }
    }
}

// MARK: - MedicationForm

/// The physical form of a medication, stored as a raw String in Medication.formRaw.
enum MedicationForm: String, Codable, CaseIterable, Identifiable {
    case tablet, capsule, liquid, injection, inhaler, topical, drops, patch, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tablet:    return NSLocalizedString("Tablet",    comment: "Medication form")
        case .capsule:   return NSLocalizedString("Capsule",   comment: "Medication form")
        case .liquid:    return NSLocalizedString("Liquid",    comment: "Medication form")
        case .injection: return NSLocalizedString("Injection", comment: "Medication form")
        case .inhaler:   return NSLocalizedString("Inhaler",   comment: "Medication form")
        case .topical:   return NSLocalizedString("Topical",   comment: "Medication form")
        case .drops:     return NSLocalizedString("Drops",     comment: "Medication form")
        case .patch:     return NSLocalizedString("Patch",     comment: "Medication form")
        case .other:     return NSLocalizedString("Other",     comment: "Medication form")
        }
    }

    var sfSymbol: String {
        switch self {
        case .tablet:    return "pill.fill"
        case .capsule:   return "pill.fill"
        case .liquid:    return "drop.fill"
        case .injection: return "syringe.fill"
        case .inhaler:   return "lungs.fill"
        case .topical:   return "hand.raised.fill"
        case .drops:     return "eye.fill"
        case .patch:     return "bandage.fill"
        case .other:     return "cross.fill"
        }
    }
}

// MARK: - Private helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
