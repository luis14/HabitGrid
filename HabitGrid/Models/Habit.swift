import Foundation
import SwiftData

@Model
final class Habit {
    var id: UUID
    var name: String
    var emoji: String
    /// 6-char hex string, e.g. "34C759"
    var colorHex: String

    // ── Schedule stored as primitives ──────────────────────────────────────
    // SwiftData can't serialize Codable enums that have associated values
    // (it inspects the property graph and crashes on associated-value fields).
    // We decompose HabitSchedule into three plain scalars and reconstruct it
    // via a computed property so all existing call-sites stay unchanged.
    //
    // scheduleTypeRaw: "daily" | "weekdays" | "customDays" | "timesPerWeek"
    var scheduleTypeRaw: String
    /// Day indices (0 = Sun … 6 = Sat) for the .customDays case.
    var scheduleCustomDays: [Int]
    /// Target count for the .timesPerWeek case.
    var scheduleTimesPerWeek: Int

    /// For binary habits this is 1; for multi-times-per-day it's N.
    var targetCount: Int
    /// Time-of-day stored as a full Date; only the time components are used.
    var reminderTime: Date?
    var createdAt: Date
    var archivedAt: Date?
    /// Display order within the list.
    var sortOrder: Int

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "✅",
        colorHex: String = "34C759",
        schedule: HabitSchedule = .daily,
        targetCount: Int = 1,
        reminderTime: Date? = nil,
        createdAt: Date = Date(),
        archivedAt: Date? = nil,
        sortOrder: Int = 0
    ) {
        self.id           = id
        self.name         = name
        self.emoji        = emoji
        self.colorHex     = colorHex
        self.targetCount  = targetCount
        self.reminderTime = reminderTime
        self.createdAt    = createdAt
        self.archivedAt   = archivedAt
        self.sortOrder    = sortOrder

        // Decompose schedule into primitives
        switch schedule {
        case .daily:
            scheduleTypeRaw      = "daily"
            scheduleCustomDays   = []
            scheduleTimesPerWeek = 0
        case .weekdays:
            scheduleTypeRaw      = "weekdays"
            scheduleCustomDays   = []
            scheduleTimesPerWeek = 0
        case .customDays(let d):
            scheduleTypeRaw      = "customDays"
            scheduleCustomDays   = d
            scheduleTimesPerWeek = 0
        case .timesPerWeek(let n):
            scheduleTypeRaw      = "timesPerWeek"
            scheduleCustomDays   = []
            scheduleTimesPerWeek = n
        }
    }

    // MARK: - Computed schedule (reconstructed on the fly)

    /// Reads and writes the full `HabitSchedule` value.
    /// Backed entirely by the three primitive stored properties above.
    var schedule: HabitSchedule {
        get {
            switch scheduleTypeRaw {
            case "weekdays":     return .weekdays
            case "customDays":   return .customDays(scheduleCustomDays)
            case "timesPerWeek": return .timesPerWeek(scheduleTimesPerWeek)
            default:             return .daily
            }
        }
        set {
            switch newValue {
            case .daily:
                scheduleTypeRaw      = "daily"
                scheduleCustomDays   = []
                scheduleTimesPerWeek = 0
            case .weekdays:
                scheduleTypeRaw      = "weekdays"
                scheduleCustomDays   = []
                scheduleTimesPerWeek = 0
            case .customDays(let d):
                scheduleTypeRaw      = "customDays"
                scheduleCustomDays   = d
                scheduleTimesPerWeek = 0
            case .timesPerWeek(let n):
                scheduleTypeRaw      = "timesPerWeek"
                scheduleCustomDays   = []
                scheduleTimesPerWeek = n
            }
        }
    }

    // MARK: - Helpers

    var isArchived: Bool { archivedAt != nil }

    /// Curated palette hex values shown in the habit editor.
    static let palette: [String] = [
        "34C759", // green
        "007AFF", // blue
        "FF9500", // orange
        "FF3B30", // red
        "AF52DE", // purple
        "FF2D55", // pink
        "5AC8FA", // light blue
        "FFCC00", // yellow
        "00C7BE", // teal
        "FF6B35", // coral
    ]
}
