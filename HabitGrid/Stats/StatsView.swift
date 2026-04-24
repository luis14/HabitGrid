import SwiftUI
import SwiftData

struct StatsView: View {

    @Environment(HabitStore.self)      private var store
    @Environment(MedicationStore.self) private var medStore
    @Environment(\.modelContext) private var modelContext
    @State private var habitStats: [UUID: QuickStats] = [:]
    @State private var medStats:   [UUID: MedQuickStats] = [:]
    @State private var multiLayers: [MultiHabitContributionGraph.Layer] = []
    @State private var moodDots: [MoodDot] = []

    struct QuickStats {
        var streak: Int = 0
        var rate30: Double = 0
    }

    struct MedQuickStats {
        var streak: Int = 0
        var rate30: Double = 0
    }

    struct MoodDot: Identifiable {
        let id: Date
        let color: Color
        let level: MoodLevel?
        let label: String
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryCards
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    if !store.activeHabits.isEmpty {
                        sectionCard {
                            yearOverviewContent
                        }
                    }

                    if !moodDots.isEmpty {
                        sectionCard {
                            moodHistoryContent
                        }
                    }

                    if !store.activeHabits.isEmpty {
                        sectionCard {
                            habitListContent
                        }
                    }

                    if !medStore.activeMedications.isEmpty {
                        sectionCard {
                            medicationListContent
                        }
                    }

                    if store.activeHabits.isEmpty && medStore.activeMedications.isEmpty && moodDots.isEmpty {
                        emptyState
                    }
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("Stats")
            .background(Color(UIColor.systemBackground))
        }
        .task { await loadStats() }
        .onChange(of: store.activeHabits.count)         { _, _ in Task { await loadStats() } }
        .onChange(of: medStore.activeMedications.count) { _, _ in Task { await loadStats() } }
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                value: "\(store.activeHabits.count)",
                label: "Habits",
                icon: "list.bullet.clipboard",
                color: .accentColor
            )
            summaryCard(
                value: "\(bestStreak)",
                label: "Best streak",
                icon: "flame.fill",
                color: .orange
            )
            summaryCard(
                value: "\(avgCompletion)%",
                label: "30d avg",
                icon: "chart.bar.fill",
                color: .green
            )
        }
    }

    private func summaryCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .symbolRenderingMode(.hierarchical)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var bestStreak: Int {
        habitStats.values.map(\.streak).max() ?? 0
    }

    private var avgCompletion: Int {
        let values = habitStats.values.map(\.rate30)
        guard !values.isEmpty else { return 0 }
        return Int((values.reduce(0, +) / Double(values.count)) * 100)
    }

    // MARK: - Section card container

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    // MARK: - Year overview

    private var yearOverviewContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Year Overview", icon: "calendar", trailing: Calendar.current.component(.year, from: Date()).description)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            Group {
                if multiLayers.isEmpty {
                    Color(UIColor.tertiarySystemBackground)
                        .frame(height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 12)
                } else {
                    MultiHabitContributionGraph(layers: multiLayers)
                        .padding(.vertical, 4)
                }
            }
            .padding(.bottom, 14)
        }
    }

    // MARK: - Mood history

    private var moodHistoryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Mood", icon: "sun.and.horizon.fill")
                .padding(.horizontal, 16)
                .padding(.top, 14)

            moodSummaryRow
                .padding(.horizontal, 16)

            moodBarChart
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
    }

    private var moodSummaryRow: some View {
        let logged = moodDots.filter { $0.level != nil }
        let rawValues = logged.compactMap { $0.level?.rawValue }
        let avgRaw: Int
        if rawValues.isEmpty {
            avgRaw = 0
        } else {
            avgRaw = Int((Double(rawValues.reduce(0, +)) / Double(rawValues.count)).rounded(.toNearestOrAwayFromZero))
        }
        let avgLevel = MoodLevel(rawValue: max(1, min(5, avgRaw)))

        return HStack(spacing: 16) {
            if let level = avgLevel {
                HStack(spacing: 6) {
                    Image(systemName: level.sfSymbol)
                        .font(.title3)
                        .foregroundStyle(level.iconColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Average mood")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(level.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(level.color)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(logged.count)")
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                Text("days logged")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(UIColor.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var moodBarChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 30 days")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(moodDots) { dot in
                    VStack(spacing: 0) {
                        Capsule()
                            .fill(dot.color)
                            .frame(width: 7, height: barHeight(for: dot.level))
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .accessibilityLabel(dot.label)
                }
            }
            .frame(height: 36)

            // Week markers
            HStack {
                ForEach([0, 7, 14, 21], id: \.self) { offset in
                    if let date = Calendar.current.date(
                        byAdding: .day, value: -(29 - offset),
                        to: Calendar.current.startOfDay(for: Date())
                    ) {
                        Text(weekLabel(date))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        if offset < 21 { Spacer() }
                    }
                }
            }
        }
    }

    private func barHeight(for level: MoodLevel?) -> CGFloat {
        guard let level else { return 4 }
        let fraction = CGFloat(level.rawValue) / 5.0
        return max(6, fraction * 36)
    }

    private static let weekLabelFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    private func weekLabel(_ date: Date) -> String {
        Self.weekLabelFmt.string(from: date)
    }

    // MARK: - Habit list

    private var habitListContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Habits", icon: "list.bullet.clipboard", trailing: "\(store.activeHabits.count)")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ForEach(Array(store.activeHabits.enumerated()), id: \.element.id) { i, habit in
                NavigationLink {
                    HabitStatsView(habit: habit)
                } label: {
                    habitRow(habit)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if i < store.activeHabits.count - 1 {
                    Divider().padding(.leading, 70)
                }
            }
            Spacer(minLength: 6)
        }
        .padding(.bottom, 8)
    }

    private func habitRow(_ habit: Habit) -> some View {
        let qs = habitStats[habit.id] ?? QuickStats()
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: habit.colorHex).opacity(0.14))
                    .frame(width: 44, height: 44)
                HabitSymbolView(habit.emoji, color: Color(hex: habit.colorHex), size: .title3)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    if qs.streak > 0 {
                        Label("\(qs.streak)d", systemImage: "flame.fill")
                            .foregroundStyle(.orange)
                    }
                    Text("\(Int(qs.rate30 * 100))%")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            Spacer()

            CompletionRing(progress: qs.rate30, color: Color(hex: habit.colorHex))
                .frame(width: 30, height: 30)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(UIColor.tertiaryLabel))
        }
    }

    // MARK: - Medication list

    private var medicationListContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Medications", icon: "pill.fill", trailing: "\(medStore.activeMedications.count)")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ForEach(Array(medStore.activeMedications.enumerated()), id: \.element.id) { i, med in
                NavigationLink {
                    MedStatsView(medication: med)
                } label: {
                    medRow(med)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if i < medStore.activeMedications.count - 1 {
                    Divider().padding(.leading, 70)
                }
            }
            Spacer(minLength: 6)
        }
        .padding(.bottom, 8)
    }

    private func medRow(_ med: Medication) -> some View {
        let qs = medStats[med.id] ?? MedQuickStats()
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: med.colorHex).opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: med.emoji)
                    .font(.title3)
                    .foregroundStyle(Color(hex: med.colorHex))
                    .symbolRenderingMode(.monochrome)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(med.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    if qs.streak > 0 {
                        Label("\(qs.streak)d", systemImage: "flame.fill")
                            .foregroundStyle(.orange)
                    }
                    Text("\(Int(qs.rate30 * 100))%")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            Spacer()

            CompletionRing(progress: qs.rate30, color: Color(hex: med.colorHex))
                .frame(width: 30, height: 30)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(UIColor.tertiaryLabel))
        }
    }

    // MARK: - Section header helper

    private func sectionHeader(_ title: String, icon: String, trailing: String? = nil) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Spacer()
            if let t = trailing {
                Text(t)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text("No stats yet")
                .font(.title3.weight(.semibold))
            Text("Create habits in the Habits tab, then come back here to see your progress.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
        .padding()
    }

    // MARK: - Data loading

    private func loadStats() async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start365 = cal.date(byAdding: .day, value: -364, to: today) ?? today

        var newStats: [UUID: QuickStats] = [:]
        var layers: [MultiHabitContributionGraph.Layer] = []

        for habit in store.activeHabits {
            let streak = (try? store.currentStreak(for: habit)) ?? 0
            let rate   = (try? store.completionRate(for: habit, days: 30)) ?? 0
            newStats[habit.id] = QuickStats(streak: streak, rate30: rate)

            let comps = (try? store.completions(for: habit, from: start365, to: today)) ?? []
            var map: [Date: ContributionEntry] = [:]
            for c in comps {
                map[c.date] = ContributionEntry(
                    intensity: HabitStore.intensityBucket(count: c.count, targetCount: habit.targetCount),
                    count: c.count
                )
            }
            layers.append(.init(colorHex: habit.colorHex, entries: map))
        }

        habitStats  = newStats
        multiLayers = layers

        var newMedStats: [UUID: MedQuickStats] = [:]
        for med in medStore.activeMedications {
            let streak = (try? medStore.currentAdherenceStreak(for: med)) ?? 0
            let rate   = (try? medStore.adherenceRate(for: med, days: 30)) ?? 0
            newMedStats[med.id] = MedQuickStats(streak: streak, rate30: rate)
        }
        medStats = newMedStats

        let start30 = cal.date(byAdding: .day, value: -29, to: today) ?? today
        var moodDescriptor = FetchDescriptor<MoodEntry>(
            predicate: #Predicate { $0.date >= start30 && $0.date <= today },
            sortBy: [SortDescriptor(\.date)]
        )
        moodDescriptor.fetchLimit = 300   // 30 days × max 10 logs/day
        let entries = (try? modelContext.fetch(moodDescriptor)) ?? []
        var moodMap: [Date: [MoodEntry]] = [:]
        for entry in entries { moodMap[entry.date, default: []].append(entry) }

        moodDots = (0..<30).map { i in
            let date = cal.date(byAdding: .day, value: -(29 - i), to: today) ?? today
            if let dayEntries = moodMap[date], !dayEntries.isEmpty {
                let sum = dayEntries.map(\.levelRaw).reduce(0, +)
                let avg = Int((Double(sum) / Double(dayEntries.count)).rounded(.toNearestOrAwayFromZero))
                let level = MoodLevel(rawValue: max(1, min(5, avg))) ?? .okay
                return MoodDot(id: date, color: level.color.opacity(0.85), level: level, label: level.label)
            }
            return MoodDot(id: date, color: Color(UIColor.systemGray5), level: nil, label: "No entry")
        }
    }
}

// MARK: - Completion ring

private struct CompletionRing: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    StatsView()
        .environment(HabitStore(context: MockData.previewContainer.mainContext))
        .environment(MedicationStore(context: MockData.previewContainer.mainContext))
        .modelContainer(MockData.previewContainer)
}
#endif
