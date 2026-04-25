import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct HabitEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Timeline provider

struct HabitProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitEntry {
        HabitEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitEntry) -> Void) {
        completion(HabitEntry(date: .now, snapshot: WidgetDataProvider.snapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitEntry>) -> Void) {
        let snapshot = WidgetDataProvider.snapshot()
        let entry = HabitEntry(date: .now, snapshot: snapshot)
        let cal = Calendar.current
        let midnight = cal.startOfDay(
            for: cal.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

// MARK: - Shared completion ring

private struct CompletionRingView: View {
    let progress: Double
    let colorHex: String
    let completed: Int
    let total: Int

    private var color: Color { Color(hex: colorHex) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 7)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(completed)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("of \(total)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Small widget view

private struct SmallWidgetView: View {
    let entry: HabitEntry

    private var accentHex: String {
        entry.snapshot.topHabits.first?.colorHex ?? "34C759"
    }

    var body: some View {
        VStack(spacing: 8) {
            CompletionRingView(
                progress: entry.snapshot.progress,
                colorHex: accentHex,
                completed: entry.snapshot.completedToday,
                total: entry.snapshot.totalToday
            )
            .frame(width: 88, height: 88)

            Text(entry.snapshot.totalToday == 0 ? "Nothing today" : "habits done")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Medium widget view

private struct MediumWidgetView: View {
    let entry: HabitEntry

    private var accentHex: String {
        entry.snapshot.topHabits.first?.colorHex ?? "34C759"
    }

    var body: some View {
        HStack(spacing: 14) {
            CompletionRingView(
                progress: entry.snapshot.progress,
                colorHex: accentHex,
                completed: entry.snapshot.completedToday,
                total: entry.snapshot.totalToday
            )
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                if entry.snapshot.topHabits.isEmpty {
                    Text("No habits due today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entry.snapshot.topHabits) { row in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: row.colorHex))
                                .frame(width: 6, height: 6)
                            Text(row.name)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(row.isComplete ? Color.secondary : Color.primary)
                                .strikethrough(row.isComplete, color: .secondary)
                            Spacer(minLength: 0)
                            Image(systemName: row.isComplete
                                  ? "checkmark.circle.fill"
                                  : "circle")
                                .font(.caption2)
                                .foregroundStyle(
                                    row.isComplete
                                    ? Color(hex: row.colorHex)
                                    : Color(UIColor.systemGray4)
                                )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Widget definitions

struct HabitGridSmallWidget: Widget {
    let kind = "HabitGridSmallWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitProvider()) { entry in
            SmallWidgetView(entry: entry)
        }
        .configurationDisplayName("HabitGrid")
        .description("Today's habit completion ring.")
        .supportedFamilies([.systemSmall])
    }
}

struct HabitGridMediumWidget: Widget {
    let kind = "HabitGridMediumWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitProvider()) { entry in
            MediumWidgetView(entry: entry)
        }
        .configurationDisplayName("HabitGrid")
        .description("Today's habits at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Widget bundle

@main
struct HabitGridWidgetBundle: WidgetBundle {
    var body: some Widget {
        HabitGridSmallWidget()
        HabitGridMediumWidget()
    }
}
