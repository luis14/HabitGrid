import SwiftUI
import SwiftData

@main
struct HabitGridApp: App {

    @AppStorage("hasOnboarded")  private var hasOnboarded  = false
    @AppStorage("themeOverride") private var themeOverride = "system"

    private static let container: ModelContainer = {
        let schema = Schema([
            Habit.self, HabitCompletion.self, MoodEntry.self,
            Medication.self, MedicationDose.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            #if DEBUG
            // Schema changed — wipe dev store and start fresh
            if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
               let storeFiles = try? FileManager.default.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil) {
                storeFiles
                    .filter { $0.pathExtension == "store" || $0.lastPathComponent.contains(".store") }
                    .forEach { try? FileManager.default.removeItem(at: $0) }
            }
            do {
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Failed to create ModelContainer after wipe: \(error)")
            }
            #else
            fatalError("Failed to create ModelContainer: \(error)")
            #endif
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppRootView(hasOnboarded: $hasOnboarded)
                .preferredColorScheme(colorScheme)
        }
        .modelContainer(Self.container)
    }

    private var colorScheme: ColorScheme? {
        switch themeOverride {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}

// MARK: - Root view

/// Bridges the SwiftData environment into both stores, handles onboarding,
/// and seeds mock data in DEBUG mode on first launch.
struct AppRootView: View {

    @Binding var hasOnboarded: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var store: HabitStore?
    @State private var medStore: MedicationStore?

    var body: some View {
        Group {
            if let store, let medStore {
                if hasOnboarded {
                    ContentView()
                        .environment(store)
                        .environment(medStore)
                } else {
                    OnboardingView {
                        hasOnboarded = true
                    }
                }
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            guard store == nil else { return }
            let s  = HabitStore(context: modelContext)
            let ms = MedicationStore(context: modelContext)
            store    = s
            medStore = ms

            // Sweep overdue doses and materialize today's on startup
            try? ms.sweepMissed()
            for med in ms.activeMedications {
                try? ms.materializeDoses(for: med, through: Date())
            }

            // Schedule one-shot follow-up reminders for any pending doses today
            let dueDoses = (try? ms.dosesDue(on: Date())) ?? []
            let medMap = Dictionary(uniqueKeysWithValues: ms.activeMedications.map { ($0.id, $0) })
            Task { @MainActor in
                for dose in dueDoses {
                    guard let med = medMap[dose.medicationID] else { continue }
                    await NotificationService.shared.scheduleFollowUps(for: dose, medication: med)
                }
            }

            #if DEBUG
            seedIfEmpty(store: s, medStore: ms)
            #endif
        }
    }

    // MARK: - Debug seeding

    #if DEBUG
    private func seedIfEmpty(store: HabitStore, medStore: MedicationStore) {
        guard store.activeHabits.isEmpty else { return }
        let habits = MockData.habits
        habits.forEach { modelContext.insert($0) }
        MockData.completions(for: habits).forEach { modelContext.insert($0) }
        let meds = MockData.medications
        meds.forEach { modelContext.insert($0) }
        MockData.medicationDoses(for: meds).forEach { modelContext.insert($0) }
        try? modelContext.save()
        store.refresh()
        medStore.refresh()
    }
    #endif
}
