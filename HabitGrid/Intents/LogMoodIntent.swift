import AppIntents
import SwiftData
import Foundation

struct LogMoodIntent: AppIntent {

    static let title: LocalizedStringResource = "Log Mood"
    static let description = IntentDescription("Record your current mood.")

    @Parameter(title: "Mood", requestValueDialog: IntentDialog("How are you feeling? (rough, low, okay, good, great)"))
    var moodName: String

    @Parameter(title: "Note", description: "Optional note about your mood.", requestValueDialog: IntentDialog("Any notes? (optional)"))
    var note: String?

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        let level = parseMood(moodName)
        let container = try IntentModelContainer.make()
        let context = ModelContext(container)
        context.insert(MoodEntry(date: Date(), level: level, note: note?.isEmpty == false ? note : nil))
        try context.save()
        return .result(dialog: "Logged mood: \(level.label).")
    }

    private func parseMood(_ input: String) -> MoodLevel {
        switch input.lowercased().trimmingCharacters(in: .whitespaces) {
        case "rough", "1": return .rough
        case "low", "2":   return .low
        case "okay", "ok", "3": return .okay
        case "good", "4":  return .good
        case "great", "5": return .great
        default:           return .okay
        }
    }
}
