import Foundation
import SwiftData

/// A single prescription or supplement the user wants to track.
///
/// Schedule and form enums are decomposed to plain scalar stored properties
/// (same pattern as `Habit` / `HabitSchedule`) because SwiftData cannot persist
/// Codable enums that have associated values.
@Model
final class Medication {
    var id: UUID
    var name: String
    /// SF Symbol name (e.g. "pill.fill") — uses HabitSymbolView for rendering.
    var emoji: String
    /// 6-char hex string, reuses Habit.palette.
    var colorHex: String
    /// Free-text strength, e.g. "10 mg" or "500 mg".
    var strength: String
    /// MedicationForm.rawValue — exposed as computed `form`.
    var formRaw: String
    var prescriber: String?

    // ── Schedule stored as primitives ──────────────────────────────────────
    // "daily" | "weekdays" | "customDays" | "asNeeded"
    var scheduleTypeRaw: String
    /// Day indices (0 = Sun … 6 = Sat) for the .customDays case.
    var scheduleCustomDays: [Int]

    // ── Dose times ─────────────────────────────────────────────────────────
    /// Each element is a Date whose only meaningful components are hour and minute.
    /// E.g. two doses per day → two entries at 08:00 and 20:00.
    var dosesPerDay: [Date]

    var startDate: Date
    var endDate: Date?
    var refillDate: Date?

    var notes: String?
    var archivedAt: Date?
    var createdAt: Date
    var sortOrder: Int

    // ── Inventory ──────────────────────────────────────────────────────────
    /// nil = not tracking inventory; ≥0 = current pill count.
    var pillCount: Int?
    /// Pills consumed per dose (default 1).
    var pillsPerDose: Int
    /// Send a low-stock alert when pillCount drops to this value or below.
    var lowStockThreshold: Int

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "pills.fill",
        colorHex: String = Habit.palette[1],    // blue
        strength: String = "",
        form: MedicationForm = .tablet,
        prescriber: String? = nil,
        schedule: MedicationSchedule = .daily,
        dosesPerDay: [Date] = [],
        startDate: Date = Date(),
        endDate: Date? = nil,
        refillDate: Date? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        archivedAt: Date? = nil,
        sortOrder: Int = 0,
        pillCount: Int? = nil,
        pillsPerDose: Int = 1,
        lowStockThreshold: Int = 7
    ) {
        self.id          = id
        self.name        = name
        self.emoji       = emoji
        self.colorHex    = colorHex
        self.strength    = strength
        self.formRaw     = form.rawValue
        self.prescriber  = prescriber
        self.dosesPerDay = dosesPerDay
        self.startDate   = Calendar.current.startOfDay(for: startDate)
        self.endDate     = endDate.map { Calendar.current.startOfDay(for: $0) }
        self.refillDate  = refillDate.map { Calendar.current.startOfDay(for: $0) }
        self.notes       = notes
        self.createdAt         = createdAt
        self.archivedAt        = archivedAt
        self.sortOrder         = sortOrder
        self.pillCount         = pillCount
        self.pillsPerDose      = max(1, pillsPerDose)
        self.lowStockThreshold = max(0, lowStockThreshold)

        // Decompose schedule into primitives
        switch schedule {
        case .daily:
            scheduleTypeRaw    = "daily"
            scheduleCustomDays = []
        case .weekdays:
            scheduleTypeRaw    = "weekdays"
            scheduleCustomDays = []
        case .customDays(let d):
            scheduleTypeRaw    = "customDays"
            scheduleCustomDays = d
        case .asNeeded:
            scheduleTypeRaw    = "asNeeded"
            scheduleCustomDays = []
        }
    }

    // MARK: - Computed properties (reconstructed on the fly)

    var form: MedicationForm {
        get { MedicationForm(rawValue: formRaw) ?? .other }
        set { formRaw = newValue.rawValue }
    }

    var schedule: MedicationSchedule {
        get {
            switch scheduleTypeRaw {
            case "weekdays":   return .weekdays
            case "customDays": return .customDays(scheduleCustomDays)
            case "asNeeded":   return .asNeeded
            default:           return .daily
            }
        }
        set {
            switch newValue {
            case .daily:
                scheduleTypeRaw    = "daily"
                scheduleCustomDays = []
            case .weekdays:
                scheduleTypeRaw    = "weekdays"
                scheduleCustomDays = []
            case .customDays(let d):
                scheduleTypeRaw    = "customDays"
                scheduleCustomDays = d
            case .asNeeded:
                scheduleTypeRaw    = "asNeeded"
                scheduleCustomDays = []
            }
        }
    }

    var isArchived: Bool { archivedAt != nil }
}
