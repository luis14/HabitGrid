import SwiftUI
import Charts

// MARK: - Period selector

enum StatsPeriod: String, CaseIterable, Identifiable {
    case days30  = "30d"
    case days90  = "90d"
    case days365 = "1y"
    var id: String { rawValue }
    var days: Int {
        switch self { case .days30: 30; case .days90: 90; case .days365: 365 }
    }
}

// MARK: - Loaded stats bundle

private struct HabitStats {
    var currentStreak: Int  = 0
    var longestStreak: Int  = 0
    var completionRate: Double = 0
    var weekdayCounts: [Int] = Array(repeating: 0, count: 7)
    var graphEntries: [Date: ContributionEntry] = [:]
}

// MARK: - View

struct HabitStatsView: View {

    let habit: Habit
    @Environment(HabitStore.self) private var store
    @State private var period: StatsPeriod = .days90
    @State private var stats = HabitStats()
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                periodPicker
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    contributionSection
                    statsCardsSection
                    weekdaySection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HabitSymbolView(habit.emoji, color: Color(hex: habit.colorHex), size: .title3)
            }
        }
        .task { await load() }
        .onChange(of: period) { _, _ in Task { await load() } }
    }

    // MARK: - Period picker

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(StatsPeriod.allCases) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 8)
    }

    // MARK: - Contribution graph

    private var contributionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contribution")
                .font(.headline)

            ContributionGraph(
                entries: stats.graphEntries,
                colorHex: habit.colorHex,
                cellSize: 12,
                cellSpacing: 2.5,
                cornerRadius: 2.5
            )
            .frame(height: 120)
            .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Stats cards

    private var statsCardsSection: some View {
        HStack(spacing: 12) {
            StatCard(
                value: "\(stats.currentStreak)",
                label: "Current\nStreak",
                icon: "flame.fill",
                iconColor: .orange,
                accentHex: habit.colorHex
            )
            StatCard(
                value: "\(stats.longestStreak)",
                label: "Longest\nStreak",
                icon: "trophy.fill",
                iconColor: .yellow,
                accentHex: habit.colorHex
            )
            StatCard(
                value: "\(Int(stats.completionRate * 100))%",
                label: "Done in\n\(period.rawValue)",
                icon: "checkmark.circle.fill",
                iconColor: Color(hex: habit.colorHex),
                accentHex: habit.colorHex
            )
        }
    }

    // MARK: - Weekday chart

    private var weekdaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By Day of Week")
                .font(.headline)

            WeekdayBarChart(counts: stats.weekdayCounts, colorHex: habit.colorHex)
                .frame(height: 160)
                .padding()
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Data loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -(period.days - 1), to: today) else { return }

        // Always load full 365 days for the graph regardless of period picker
        let graphStart = cal.date(byAdding: .day, value: -364, to: today) ?? start

        let allComps = (try? store.completions(for: habit, from: graphStart, to: today)) ?? []
        let periodComps = allComps.filter { $0.date >= start }

        // Graph entries
        var graphEntries: [Date: ContributionEntry] = [:]
        for c in allComps {
            graphEntries[c.date] = ContributionEntry(
                intensity: HabitStore.intensityBucket(count: c.count, targetCount: habit.targetCount),
                count: c.count
            )
        }

        // Weekday counts (from period window)
        var wdCounts = Array(repeating: 0, count: 7)
        for c in periodComps where c.count > 0 {
            wdCounts[cal.component(.weekday, from: c.date) - 1] += 1
        }

        // Completion rate
        let rate = (try? store.completionRate(for: habit, days: period.days)) ?? 0

        stats = HabitStats(
            currentStreak:  (try? store.currentStreak(for: habit)) ?? 0,
            longestStreak:  (try? store.longestStreak(for: habit)) ?? 0,
            completionRate: rate,
            weekdayCounts:  wdCounts,
            graphEntries:   graphEntries
        )
    }
}

// MARK: - Stat card

private struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let iconColor: Color
    let accentHex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .font(.title3)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Weekday bar chart

private struct WeekdayBarChart: View {
    let counts: [Int]   // index 0 = Sun … 6 = Sat
    let colorHex: String

    private let labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        Chart {
            ForEach(0..<7, id: \.self) { i in
                BarMark(
                    x: .value("Day", labels[i]),
                    y: .value("Completions", counts[i])
                )
                .foregroundStyle(
                    Color(hex: colorHex).gradient
                )
                .cornerRadius(5)
                .annotation(position: .top, alignment: .center) {
                    if counts[i] > 0 {
                        Text("\(counts[i])")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisValueLabel()
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel()
                    .font(.caption2)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    NavigationStack {
        HabitStatsView(habit: MockData.habits[0])
            .environment(HabitStore(context: MockData.previewContainer.mainContext))
            .modelContainer(MockData.previewContainer)
    }
}
#endif
