import AppIntents

struct HabitGridShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogHabitIntent(),
            phrases: [
                "Log \(\.$habitName) in \(.applicationName)",
                "Mark \(\.$habitName) done in \(.applicationName)",
                "Complete \(\.$habitName) in \(.applicationName)"
            ],
            shortTitle: "Log Habit",
            systemImageName: "checkmark.circle.fill"
        )

        AppShortcut(
            intent: MarkMedicationTakenIntent(),
            phrases: [
                "Take \(\.$medicationName) in \(.applicationName)",
                "Mark \(\.$medicationName) taken in \(.applicationName)",
                "Log \(\.$medicationName) dose in \(.applicationName)"
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
