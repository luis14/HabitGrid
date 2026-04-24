import Foundation
import SwiftUI
import SwiftData

// MARK: - Mood level

enum MoodLevel: Int, CaseIterable, Codable, Identifiable {
    case rough = 1, low = 2, okay = 3, good = 4, great = 5

    var id: Int { rawValue }

    var sfSymbol: String {
        switch self {
        case .rough: "cloud.heavyrain.fill"
        case .low:   "cloud.drizzle.fill"
        case .okay:  "cloud.sun.fill"
        case .good:  "sun.min.fill"
        case .great: "sun.max.fill"
        }
    }

    // Single explicit color per symbol — palette/multicolor both fall back to
    // the env tint for symbols without native multi-layer support (e.g. sun.fill).
    var iconColor: Color {
        switch self {
        case .rough: Color(red: 0.50, green: 0.70, blue: 1.00) // rain blue
        case .low:   Color(red: 1.00, green: 0.60, blue: 0.20) // soft amber
        case .okay:  Color(red: 1.00, green: 0.80, blue: 0.00) // yellow
        case .good:  Color(red: 1.00, green: 0.60, blue: 0.00) // warm orange
        case .great: Color(red: 1.00, green: 0.45, blue: 0.00) // deep orange
        }
    }

    var label: String {
        switch self {
        case .rough: NSLocalizedString("Rough", comment: "Mood level")
        case .low:   NSLocalizedString("Low",   comment: "Mood level")
        case .okay:  NSLocalizedString("Okay",  comment: "Mood level")
        case .good:  NSLocalizedString("Good",  comment: "Mood level")
        case .great: NSLocalizedString("Great", comment: "Mood level")
        }
    }

    var color: Color {
        switch self {
        case .rough: .red
        case .low:   .orange
        case .okay:  .yellow
        case .good:  .blue
        case .great: .green
        }
    }
}

// MARK: - Model

/// One mood log per check-in. Multiple logs allowed per calendar day.
/// `date` is normalised to startOfDay for day-based grouping; `timestamp`
/// records the exact moment the user logged their mood.
@Model
final class MoodEntry {
    var id: UUID
    /// Normalised to start of day — used for grouping and fetching by day.
    var date: Date
    /// Exact log time — used for sorting multiple entries within a day.
    var timestamp: Date
    var levelRaw: Int
    var note: String?

    init(id: UUID = UUID(), date: Date = Date(), level: MoodLevel, note: String? = nil) {
        self.id        = id
        self.date      = Calendar.current.startOfDay(for: date)
        self.timestamp = date
        self.levelRaw  = level.rawValue
        self.note      = note
    }

    var level: MoodLevel {
        get { MoodLevel(rawValue: levelRaw) ?? .okay }
        set { levelRaw = newValue.rawValue }
    }
}
