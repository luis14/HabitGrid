import Foundation
import SwiftData
import SwiftUI

/// One scheduled (or PRN) dose log for a medication.
///
/// `scheduledAt` is the source of truth for what was planned.
/// `date` is denormalised to `startOfDay(scheduledAt)` for fast day-level
/// predicate filtering — the same pattern as `HabitCompletion.date`.
/// `takenAt` lets the user log a dose late without losing the scheduled time.
@Model
final class MedicationDose {
    var id: UUID
    /// Denormalized FK — same pattern as HabitCompletion.habitID.
    var medicationID: UUID
    /// Exact planned datetime (includes hour and minute).
    var scheduledAt: Date
    /// Normalised to startOfDay(scheduledAt) — used for fast daily queries.
    var date: Date
    /// Set when the user marks the dose taken; nil until then.
    var takenAt: Date?
    /// DoseStatus.rawValue — exposed as computed `status`.
    var statusRaw: String
    var note: String?

    // MARK: - Init

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        scheduledAt: Date,
        takenAt: Date? = nil,
        status: DoseStatus = .pending,
        note: String? = nil
    ) {
        self.id           = id
        self.medicationID = medicationID
        self.scheduledAt  = scheduledAt
        self.date         = Calendar.current.startOfDay(for: scheduledAt)
        self.takenAt      = takenAt
        self.statusRaw    = status.rawValue
        self.note         = note
    }

    // MARK: - Computed status

    var status: DoseStatus {
        get { DoseStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}

// MARK: - DoseStatus

enum DoseStatus: String, Codable, CaseIterable {
    case pending, taken, skipped, missed

    var label: String {
        switch self {
        case .pending: return "Pending"
        case .taken:   return "Taken"
        case .skipped: return "Skipped"
        case .missed:  return "Missed"
        }
    }

    var sfSymbol: String {
        switch self {
        case .pending: return "circle"
        case .taken:   return "checkmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .missed:  return "xmark.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .pending: return Color.secondary
        case .taken:   return Color.green
        case .skipped: return Color.gray
        case .missed:  return Color.red
        }
    }
}
