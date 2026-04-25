import SwiftUI
import Charts
import SwiftData

// MARK: - Data model

private struct DayPoint: Identifiable {
    let id = UUID()
    let date: Date
    let moodScore: Double      // 1–5
    let completed: Bool
}

private struct CorrelationData {
    let points: [DayPoint]
    var completedAvg: Double {
        let s = points.filter(\.completed); guard !s.isEmpty else { return 0 }
        return s.reduce(0) { $0 + $1.moodScore } / Double(s.count)
    }
    var notCompletedAvg: Double {
        let s = points.filter { !$0.completed }; guard !s.isEmpty else { return 0 }
        return s.reduce(0) { $0 + $1.moodScore } / Double(s.count)
    }
    var hasEnoughData: Bool { points.count >= 14 }
    var moodLift: Double { completedAvg - notCompletedAvg }
}

// MARK: - Card view

/// Displays average mood on habit-completed days vs scheduled-but-skipped days.
/// Requires ≥ 14 days with both mood and scheduled-day overlap before rendering.
struct MoodHabitCorrelationCard: View {

    let habit: Habit
    @Environment(HabitStore.self) private var store
    @Environment(\.modelContext) private var context

    @State private var data: CorrelationData?
    @State private var isLoading = true

    private static let lookbackDays = 90

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if let data, data.hasEnoughData {
                cardContent(data)
            }
            // shows nothing when insufficient data — caller wraps with VStack
        }
        .task { await load() }
    }

    // MARK: - Card layout

    private func cardContent(_ data: CorrelationData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
                Text("Mood & Habit")
                    .font(.headline)
                Spacer()
                moodLiftBadge(data.moodLift)
            }

            averageBarChart(data)
                .frame(height: 120)

            caption(data)
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Sub-views

    private func averageBarChart(_ data: CorrelationData) -> some View {
        let bars: [(label: String, value: Double, color: Color)] = [
            ("Completed", data.completedAvg,    .green),
            ("Skipped",   data.notCompletedAvg, .orange)
        ]
        return Chart(bars, id: \.label) { bar in
            BarMark(
                x: .value("State", bar.label),
                y: .value("Avg Mood", bar.value)
            )
            .foregroundStyle(bar.color.gradient)
            .cornerRadius(8)
            .annotation(position: .top, alignment: .center) {
                Text(String(format: "%.1f", bar.value))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYScale(domain: 1...5)
        .chartYAxis {
            AxisMarks(values: [1, 2, 3, 4, 5]) { val in
                AxisGridLine()
                AxisValueLabel {
                    if let i = val.as(Int.self) {
                        Text(moodLabel(i))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { AxisValueLabel().font(.caption) }
        }
    }

    private func moodLiftBadge(_ lift: Double) -> some View {
        let positive = lift >= 0
        let sign = positive ? "+" : ""
        return Label(
            "\(sign)\(String(format: "%.1f", lift)) pts",
            systemImage: positive ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(positive ? .green : .orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((positive ? Color.green : Color.orange).opacity(0.12),
                    in: Capsule())
    }

    private func caption(_ data: CorrelationData) -> some View {
        let doneCount = data.points.filter(\.completed).count
        let skipCount = data.points.filter { !$0.completed }.count
        return Text("\(doneCount) completed days · \(skipCount) scheduled-but-skipped · last \(Self.lookbackDays) days")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Data loading

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -(Self.lookbackDays - 1), to: today) else { return }

        // Fetch habit completions
        let completions = (try? store.completions(for: habit, from: start, to: today)) ?? []
        let completedSet = Set(completions.filter { $0.count > 0 }.map { cal.startOfDay(for: $0.date) })

        // Fetch mood entries
        var moodDescriptor = FetchDescriptor<MoodEntry>(
            predicate: #Predicate { $0.date >= start && $0.date <= today },
            sortBy: [SortDescriptor(\.date)]
        )
        moodDescriptor.fetchLimit = 400
        let moods = (try? context.fetch(moodDescriptor)) ?? []

        // Build per-day avg mood map (multiple entries per day → average)
        var moodByDay: [Date: [Double]] = [:]
        for entry in moods {
            let day = cal.startOfDay(for: entry.date)
            moodByDay[day, default: []].append(Double(entry.levelRaw))
        }
        let avgMoodByDay = moodByDay.mapValues { $0.reduce(0, +) / Double($0.count) }

        // Build correlation points: only scheduled days that also have a mood log
        var points: [DayPoint] = []
        var cursor = start
        while cursor <= today {
            if habit.schedule.isDue(on: cursor, calendar: cal),
               let moodScore = avgMoodByDay[cursor] {
                let completed = completedSet.contains(cursor)
                points.append(DayPoint(date: cursor, moodScore: moodScore, completed: completed))
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        data = CorrelationData(points: points)
    }

    // MARK: - Helpers

    private func moodLabel(_ score: Int) -> String {
        MoodLevel(rawValue: score)?.label ?? "\(score)"
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        ScrollView {
            MoodHabitCorrelationCard(habit: MockData.habits[0])
                .environment(HabitStore(context: MockData.previewContainer.mainContext))
                .modelContainer(MockData.previewContainer)
                .padding()
        }
    }
}
#endif
