import Foundation
import SwiftData

@Model
final class HabitCompletion {
    var id: UUID
    /// Denormalized foreign key (UUID) for efficient predicate filtering.
    var habitID: UUID
    /// Stored as midnight of the local calendar day (no time component).
    var date: Date
    var count: Int
    var note: String?

    init(
        id: UUID = UUID(),
        habitID: UUID,
        date: Date,
        count: Int = 1,
        note: String? = nil
    ) {
        self.id = id
        self.habitID = habitID
        self.date = Calendar.current.startOfDay(for: date)
        self.count = count
        self.note = note
    }
}
