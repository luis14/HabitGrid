import SwiftUI

/// A compact, non-scrollable 12-week contribution graph shown on habit list rows.
/// Uses the same color shading as `ContributionGraph` but renders inline.
struct MiniContributionGraph: View {

    let entries: [Date: ContributionEntry]
    let colorHex: String
    var cellSize: CGFloat   = 8
    var cellSpacing: CGFloat = 1.5
    var weeks: Int          = 12
    var cornerRadius: CGFloat = 1.5

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: cellSpacing) {
            ForEach(0 ..< weeks, id: \.self) { w in
                VStack(spacing: cellSpacing) {
                    ForEach(0 ..< 7, id: \.self) { d in
                        let day = date(weekOffset: w, dayOffset: d)
                        let entry = day <= today ? entries[day] : nil
                        let active = day <= today && day >= windowStart
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(color(intensity: active ? (entry?.intensity ?? 0) : 0, active: active))
                            .frame(width: cellSize, height: cellSize)
                            .animation(.easeInOut(duration: 0.2), value: entry?.intensity ?? 0)
                    }
                }
            }
        }
        .accessibilityHidden(true) // detail graph in stats provides the semantic info
    }

    // MARK: Helpers

    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private var windowStart: Date {
        cal.date(byAdding: .day, value: -(weeks * 7 - 1), to: today) ?? today
    }

    /// Returns the date for a cell given week (0 = oldest) and day (0 = Sun) offsets.
    private func date(weekOffset w: Int, dayOffset d: Int) -> Date {
        // Align grid end to Saturday (or end of week) containing today
        let rawWD = cal.component(.weekday, from: today) - 1  // 0=Sun
        let daysToSat = 6 - rawWD
        let gridEnd = cal.date(byAdding: .day, value: daysToSat, to: today)!
        let gridStart = cal.date(byAdding: .day, value: -(weeks * 7 - 1), to: gridEnd)!
        return cal.date(byAdding: .day, value: w * 7 + d, to: gridStart) ?? today
    }

    private func color(intensity: Int, active: Bool) -> Color {
        guard active else {
            return colorScheme == .dark ? Color(white: 0.10) : Color(UIColor.systemGray6)
        }
        return .contribution(intensity: intensity, hex: colorHex, scheme: colorScheme)
    }
}

#if DEBUG
#Preview("MiniContributionGraph") {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    var entries: [Date: ContributionEntry] = [:]
    var rng = SeededRNG(seed: 99)
    for d in 0...83 {
        guard rng.nextDouble() < 0.65 else { continue }
        let date = cal.date(byAdding: .day, value: -d, to: today)!
        let i = max(1, Int(rng.nextDouble() * 4) + 1)
        entries[date] = ContributionEntry(intensity: i, count: i)
    }
    return VStack(alignment: .leading, spacing: 12) {
        MiniContributionGraph(entries: entries, colorHex: "34C759")
        MiniContributionGraph(entries: entries, colorHex: "007AFF")
        MiniContributionGraph(entries: entries, colorHex: "AF52DE")
    }
    .padding()
}
#endif
