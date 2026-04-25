import SwiftUI
import SwiftData
import WidgetKit
import UserNotifications

@main
struct HabitGridApp: App {

    @AppStorage("hasOnboarded")  private var hasOnboarded  = false
    @AppStorage("themeOverride") private var themeOverride = "system"

    // Static so the delegate is alive before any SwiftUI view is created and
    // UNUserNotificationCenter.delegate is set before the first runloop tick.
    // This guarantees cold-launch notification taps are delivered to the delegate.
    private static let router = NotificationRouter()
    private static let notifDelegate: AppNotificationDelegate = {
        let d = AppNotificationDelegate(router: HabitGridApp.router)
        UNUserNotificationCenter.current().delegate = d
        return d
    }()

    init() {
        // Force static initializer to run before the scene connects.
        _ = Self.notifDelegate
    }

    private static let container: ModelContainer = {
        let schema = Schema([
            Habit.self, HabitCompletion.self, MoodEntry.self,
            Medication.self, MedicationDose.self
        ])
        // Preferred: App Group container (shared with widget).
        if let groupConfig = appGroupConfig(schema: schema) {
            if let c = try? ModelContainer(for: schema, configurations: groupConfig) {
                return c
            }
            // Schema mismatch — wipe the App Group store and retry.
            #if DEBUG
            wipeStore()
            if let c = try? ModelContainer(for: schema, configurations: groupConfig) {
                return c
            }
            #endif
        }
        // Fallback: plain in-app store (widget won't share data, but app stays alive).
        let localConfig = ModelConfiguration(schema: schema)
        if let c = try? ModelContainer(for: schema, configurations: localConfig) {
            return c
        }
        #if DEBUG
        wipeStore()
        if let c = try? ModelContainer(for: schema, configurations: localConfig) {
            return c
        }
        #endif
        fatalError("Cannot create ModelContainer — all fallbacks exhausted.")
    }()

    /// Builds a ModelConfiguration that stores the SQLite file in the shared App Group
    /// container (accessible by both the main app and the WidgetKit extension).
    /// When iCloud sync is enabled (UserDefaults key "iCloudSyncEnabled"), the
    /// configuration additionally enables CloudKit replication.
    /// Returns nil when the App Group entitlement is absent (e.g. bare simulator).
    private static func appGroupConfig(schema: Schema) -> ModelConfiguration? {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.habitgrid.shared"
        ) else { return nil }

        // Build an explicit URL so the widget extension opens the same file.
        let libURL = groupURL.appendingPathComponent("Library/Application Support", isDirectory: true)
        try? FileManager.default.createDirectory(at: libURL, withIntermediateDirectories: true)
        let storeURL = libURL.appendingPathComponent("default.store")

        let syncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        if syncEnabled {
            return ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .private("iCloud.com.habitgrid.shared")
            )
        }
        return ModelConfiguration(schema: schema, url: storeURL)
    }

    private static func wipeStore() {
        let fm = FileManager.default
        let roots: [URL] = [
            fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.habitgrid.shared"),
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ].compactMap { $0 }

        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                if url.pathExtension == "store" || name.contains(".store") {
                    try? fm.removeItem(at: url)
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(hasOnboarded: $hasOnboarded)
                .preferredColorScheme(colorScheme)
                .environment(Self.router)
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
        MockData.moodEntries(for: habits).forEach { modelContext.insert($0) }
        let meds = MockData.medications
        meds.forEach { modelContext.insert($0) }
        MockData.medicationDoses(for: meds).forEach { modelContext.insert($0) }
        try? modelContext.save()
        store.refresh()
        medStore.refresh()
    }
    #endif
}
