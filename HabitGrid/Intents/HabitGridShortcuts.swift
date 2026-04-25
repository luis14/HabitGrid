import AppIntents

struct HabitGridShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogHabitIntent(),
            phrases: [
                "Log a habit in \(.applicationName)",
                "Mark a habit done in \(.applicationName)",
                "Complete a habit in \(.applicationName)"
            ],
            shortTitle: "Log Habit",
            systemImageName: "checkmark.circle.fill"
        )

        AppShortcut(
            intent: MarkMedicationTakenIntent(),
            phrases: [
                "Take a medication in \(.applicationName)",
                "Mark medication taken in \(.applicationName)",
                "Log a dose in \(.applicationName)"
            ],
            shortTitle: "Mark Medication Taken",
            systemImageName: "pill.fill"
        )

        AppShortcut(
            intent: LogMoodIntent(),
            phrases: [
                "Log my mood in \(.applicationName)",
                "Record mood in \(.applicationName)",
                "How am I feeling in \(.applicationName)"
            ],
            shortTitle: "Log Mood",
            systemImageName: "face.smiling.inverse"
        )
    }
}
