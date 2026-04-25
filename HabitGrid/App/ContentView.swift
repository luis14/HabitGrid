import SwiftUI

struct ContentView: View {

    @Environment(HabitStore.self)      private var store
    @Environment(MedicationStore.self) private var medStore
    @AppStorage("weekStartDay") private var weekStartDay: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            TabView {
                TodayView()
                    .tabItem { Label("Today", systemImage: "checkmark.circle.fill") }
                    .tag(0)

                HabitsListView()
                    .tabItem { Label("Habits", systemImage: "list.bullet") }
                    .tag(1)

                MedsListView()
                    .tabItem { Label("Meds", systemImage: "pill.fill") }
                    .tag(2)

                StatsView()
                    .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                    .tag(3)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(4)
            }
            .tint(.accentColor)

            NotificationCapBanner()
        }
    }
}

#if DEBUG
#Preview {
    ContentView()
        .environment(HabitStore(context: MockData.previewContainer.mainContext))
        .environment(MedicationStore(context: MockData.previewContainer.mainContext))
        .modelContainer(MockData.previewContainer)
}
#endif
