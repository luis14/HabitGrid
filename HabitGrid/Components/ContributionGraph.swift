import SwiftUI

// MARK: - Public entry type

/// One day's worth of data for the contribution graph.
struct ContributionEntry: Equatable {
    var intensity: Int    // 0–4
    var count: Int
}

private let monthFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "MMM"; return f
}()

// MARK: - Grid internals

private struct GridDay: Identifiable {
    let id: UUID = UUID()
    let date: Date
    let intensity: Int
    let count: Int
    /// True when the date is within the visible 365-day window and ≤ today.
    let isActive: Bool
}

private struct MonthLabel: Identifiable {
    let id: Int      // weekIndex
    let weekIndex: Int
    let title: String
}

/// Builds the 53×7 grid from raw entry data.
private func buildGrid(
    entries: [Date: ContributionEntry],
    referenceDate: Date,
    weekStartsOnSunday: Bool
) -> (weeks: [[GridDay]], monthLabels: [MonthLabel]) {

    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = weekStartsOnSunday ? 1 : 2

    let today = cal.startOfDay(for: referenceDate)

    // Day-of-week index within the current week (0 = week's first day)
    let rawWD  = cal.component(.weekday, from: today)   // 1-based, 1=Sun
    let firstWD = weekStartsOnSunday ? 1 : 2
    let todaySlot = (rawWD - firstWD + 7) % 7          // 0 … 6

    // Grid spans exactly 53 weeks; today sits at (week 52, row todaySlot).
    guard
        let gridEnd     = cal.date(byAdding: .day, value: 6 - todaySlot, to: today),
        let gridStart   = cal.date(byAdding: .day, value: -(53 * 7 - 1), to: gridEnd),
        let windowStart = cal.date(byAdding: .day, value: -364, to: today)
    else { return ([], []) }

    var weeks: [[GridDay]] = []
    var monthLabels: [MonthLabel] = []
    var lastLabelledMonth = -1

    for w in 0 ..< 53 {
        var week: [GridDay] = []
        var firstActiveDateInWeek: Date? = nil

        for d in 0 ..< 7 {
            let date = cal.date(byAdding: .day, value: w * 7 + d, to: gridStart)!
            let isActive = date >= windowStart && date <= today
            let entry = isActive ? entries[date] : nil

            if isActive && firstActiveDateInWeek == nil {
                firstActiveDateInWeek = date
            }

            week.append(GridDay(
                date: date,
                intensity: entry?.intensity ?? 0,
                count: entry?.count ?? 0,
                isActive: isActive
            ))
        }

        // Emit a month label when the first active day in this week starts a new month,
        // provided that day is early enough in the week (≤ 3) so the label aligns cleanly.
        if let firstDay = firstActiveDateInWeek {
            let month   = cal.component(.month, from: firstDay)
            let dayOfMo = cal.component(.day,   from: firstDay)
            if month != lastLabelledMonth && dayOfMo <= 7 {
                lastLabelledMonth = month
                monthLabels.append(MonthLabel(id: w, weekIndex: w, title: monthFormatter.string(from: firstDay)))
            }
        }

        weeks.append(week)
    }

    return (weeks, monthLabels)
}

// MARK: - Tooltip

private struct CellTooltip: View {
    let day: GridDay

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Self.dateFmt.string(from: day.date))
                .font(.caption.weight(.semibold))
            Text(countString)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var countString: String {
        switch day.count {
        case 0:  return "No completions"
        case 1:  return "1 completion"
        default: return "\(day.count) completions"
        }
    }
}

// MARK: - Single cell

private struct CellView: View {
    let day: GridDay
    let fillColor: Color
    let size: CGFloat
    let radius: CGFloat

    @State private var showTooltip = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(fillColor)
            .frame(width: size, height: size)
            // Enlarged tap target for small cells
            .contentShape(Rectangle().inset(by: -(max(0, (22 - size) / 2))))
            .animation(.easeInOut(duration: 0.22), value: fillColor)
            .accessibilityLabel(a11yLabel)
            .accessibilityAddTraits(day.isActive ? .isButton : [])
            .onTapGesture { if day.isActive { showTooltip = true } }
            .popover(isPresented: $showTooltip) {
                CellTooltip(day: day)
                    .presentationCompactAdaptation(.popover)
            }
    }

    private static let a11yDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .long; return f
    }()

    private var a11yLabel: String {
        guard day.isActive else { return "empty cell" }
        let ds = Self.a11yDateFmt.string(from: day.date)
        return day.count == 0
            ? "\(ds), no completions"
            : "\(ds), \(day.count) \(day.count == 1 ? "completion" : "completions")"
    }
}

// MARK: - ContributionGraph (single habit)

/// A GitHub-style 53×7 contribution heatmap.
///
/// ```swift
/// ContributionGraph(
///     entries: precomputedEntries,   // [Date: ContributionEntry]
///     colorHex: habit.colorHex
/// )
/// ```
///
/// - Parameters:
///   - entries: Mapping of (normalised) dates to intensity/count pairs.
///     Dates outside the 365-day window are silently ignored.
///   - colorHex: 6-char hex string for the base swatch colour.
///   - cellSize: Edge length of each square cell (default 11 pt).
///   - cellSpacing: Gap between cells (default 2 pt).
///   - cornerRadius: Corner radius of each cell (default 2 pt).
///   - weekStartsOnSunday: When `false`, Monday becomes the first row (default `true`).
struct ContributionGraph: View {
    let entries: [Date: ContributionEntry]
    let colorHex: String

    var cellSize: CGFloat      = 11
    var cellSpacing: CGFloat   = 2
    var cornerRadius: CGFloat  = 2
    var weekStartsOnSunday: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    // MARK: Grid — built once per entries/weekStartsOnSunday change

    @State private var cachedGrid: (weeks: [[GridDay]], monthLabels: [MonthLabel]) = ([], [])

    private func rebuildGrid() {
        cachedGrid = buildGrid(entries: entries, referenceDate: Date(), weekStartsOnSunday: weekStartsOnSunday)
    }

    // MARK: Layout constants

    /// Approximate pixel width of "Wed" at 9 pt.
    private var wdLabelWidth: CGFloat { 24 }

    private var stepWidth: CGFloat { cellSize + cellSpacing }

    // MARK: Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                monthHeaderRow
                HStack(alignment: .top, spacing: cellSpacing) {
                    weekdayLabelColumn
                    cellGrid
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Contribution graph, past 365 days")
        .onAppear { rebuildGrid() }
        .onChange(of: entries) { rebuildGrid() }
        .onChange(of: weekStartsOnSunday) { rebuildGrid() }
    }

    // MARK: Month header

    private var monthHeaderRow: some View {
        let labels = cachedGrid.monthLabels
        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(
                    width: wdLabelWidth + cellSpacing + CGFloat(53) * stepWidth,
                    height: 14
                )

            ForEach(labels) { label in
                Text(label.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .offset(
                        x: wdLabelWidth + cellSpacing + CGFloat(label.weekIndex) * stepWidth
                    )
            }
        }
    }

    // MARK: Weekday labels

    private var weekdayLabelColumn: some View {
        let days: [String] = weekStartsOnSunday
            ? ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
            : ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
        // Show Mon (1), Wed (3), Fri (5)
        let shown: Set<Int> = [1, 3, 5]

        return VStack(spacing: cellSpacing) {
            ForEach(0 ..< 7, id: \.self) { row in
                Text(shown.contains(row) ? days[row] : "")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: wdLabelWidth, height: cellSize, alignment: .trailing)
            }
        }
    }

    // MARK: Cell grid

    private var cellGrid: some View {
        let weeks = cachedGrid.weeks
        return HStack(alignment: .top, spacing: cellSpacing) {
            ForEach(0 ..< weeks.count, id: \.self) { w in
                VStack(spacing: cellSpacing) {
                    ForEach(weeks[w]) { day in
                        CellView(
                            day: day,
                            fillColor: color(for: day),
                            size: cellSize,
                            radius: cornerRadius
                        )
                    }
                }
            }
        }
    }

    // MARK: Cell colour helper

    private func color(for day: GridDay) -> Color {
        guard day.isActive else {
            return colorScheme == .dark ? Color(white: 0.10) : Color(UIColor.systemGray6)
        }
        return .contribution(intensity: day.intensity, hex: colorHex, scheme: colorScheme)
    }
}

// MARK: - MultiHabitContributionGraph (year overview)

/// Year overview that blends colours from multiple habits.
/// Each cell shows a circular-mean hue of all habits with completions that day,
/// weighted by their per-habit intensity.
struct MultiHabitContributionGraph: View {

    struct Layer {
        let colorHex: String
        let entries: [Date: ContributionEntry]
    }

    let layers: [Layer]
    var cellSize: CGFloat      = 11
    var cellSpacing: CGFloat   = 2
    var cornerRadius: CGFloat  = 2
    var weekStartsOnSunday: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                monthHeaderRow
                HStack(alignment: .top, spacing: cellSpacing) {
                    weekdayLabelColumn
                    cellGrid
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("All-habits year overview")
    }

    // MARK: Computed grid

    private var gridData: (weeks: [[GridDay]], monthLabels: [MonthLabel]) {
        // We compute a synthetic "blended" entries dict just for layout/tooltip counts;
        // actual colours are computed per-cell in color(for:).
        var blended: [Date: ContributionEntry] = [:]
        var allDates = Set<Date>()
        layers.forEach { allDates.formUnion($0.entries.keys) }

        for date in allDates {
            let total = layers.reduce(0) { $0 + ($1.entries[date]?.count ?? 0) }
            let avgI  = layers.reduce(0.0) { $0 + Double($1.entries[date]?.intensity ?? 0) } / Double(max(1, layers.count))
            blended[date] = ContributionEntry(intensity: Int(avgI.rounded()), count: total)
        }
        return buildGrid(entries: blended, referenceDate: Date(), weekStartsOnSunday: weekStartsOnSunday)
    }

    // MARK: Blended cell colour

    // Pre-computed hue per layer — avoids UIColor init + HSB extraction inside the hot render loop.
    private var layerHues: [(hue: Double, entries: [Date: ContributionEntry])] {
        layers.map { layer in
            let (h, _, _) = (UIColor(hex: layer.colorHex) ?? .systemGreen).contributionHSB()
            return (hue: Double(h), entries: layer.entries)
        }
    }

    private func color(for day: GridDay) -> Color {
        guard day.isActive && day.intensity > 0 else {
            return colorScheme == .dark ? Color(white: 0.10) : Color(UIColor.systemGray6)
        }

        var sinSum = 0.0, cosSum = 0.0, totalWeight = 0.0

        for layer in layerHues {
            guard let entry = layer.entries[day.date], entry.intensity > 0 else { continue }
            let w = Double(entry.intensity)
            sinSum += sin(layer.hue * 2 * .pi) * w
            cosSum += cos(layer.hue * 2 * .pi) * w
            totalWeight += w
        }

        guard totalWeight > 0 else {
            return .contribution(intensity: day.intensity, hex: "34C759", scheme: colorScheme)
        }

        var blendedH = atan2(sinSum / totalWeight, cosSum / totalWeight) / (2 * .pi)
        if blendedH < 0 { blendedH += 1 }

        // Use a fixed "good" saturation for the blended result
        let (finalS, finalB): (Double, Double)
        if colorScheme == .light {
            switch day.intensity {
            case 1:  (finalS, finalB) = (0.30, 0.94)
            case 2:  (finalS, finalB) = (0.54, 0.82)
            case 3:  (finalS, finalB) = (0.75, 0.65)
            default: (finalS, finalB) = (0.88, 0.42)
            }
        } else {
            switch day.intensity {
            case 1:  (finalS, finalB) = (0.50, 0.20)
            case 2:  (finalS, finalB) = (0.60, 0.38)
            case 3:  (finalS, finalB) = (0.70, 0.57)
            default: (finalS, finalB) = (0.78, 0.78)
            }
        }
        return Color(hue: blendedH, saturation: finalS, brightness: finalB)
    }

    // MARK: Layout (mirrors ContributionGraph)

    private var wdLabelWidth: CGFloat { 24 }
    private var stepWidth: CGFloat { cellSize + cellSpacing }

    private var monthHeaderRow: some View {
        let labels = gridData.monthLabels
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(
                width: wdLabelWidth + cellSpacing + CGFloat(53) * stepWidth,
                height: 14
            )
            ForEach(labels) { label in
                Text(label.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .offset(x: wdLabelWidth + cellSpacing + CGFloat(label.weekIndex) * stepWidth)
            }
        }
    }

    private var weekdayLabelColumn: some View {
        let days: [String] = weekStartsOnSunday
            ? ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
            : ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
        let shown: Set<Int> = [1, 3, 5]
        return VStack(spacing: cellSpacing) {
            ForEach(0 ..< 7, id: \.self) { row in
                Text(shown.contains(row) ? days[row] : "")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: wdLabelWidth, height: cellSize, alignment: .trailing)
            }
        }
    }

    private var cellGrid: some View {
        let weeks = gridData.weeks
        return HStack(alignment: .top, spacing: cellSpacing) {
            ForEach(0 ..< weeks.count, id: \.self) { w in
                VStack(spacing: cellSpacing) {
                    ForEach(weeks[w]) { day in
                        CellView(
                            day: day,
                            fillColor: color(for: day),
                            size: cellSize,
                            radius: cornerRadius
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
private func mockEntries(hex: String, seed: Int) -> [Date: ContributionEntry] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    var rng = SeededRNG(seed: seed)
    var entries: [Date: ContributionEntry] = [:]
    for daysAgo in 0...364 {
        guard rng.nextDouble() < 0.68 else { continue }
        let date = cal.date(byAdding: .day, value: -daysAgo, to: today)!
        let intensity = max(1, min(4, Int(rng.nextDouble() * 4) + 1))
        entries[date] = ContributionEntry(intensity: intensity, count: intensity * 2)
    }
    return entries
}

#Preview("Single habit — green") {
    VStack(spacing: 20) {
        ContributionGraph(
            entries: mockEntries(hex: "34C759", seed: 1),
            colorHex: "34C759"
        )
        ContributionGraph(
            entries: mockEntries(hex: "34C759", seed: 1),
            colorHex: "34C759",
            cellSize: 14,
            cellSpacing: 3,
            cornerRadius: 3
        )
    }
    .padding()
}

#Preview("Single habit — blue", traits: .sizeThatFitsLayout) {
    ContributionGraph(
        entries: mockEntries(hex: "007AFF", seed: 2),
        colorHex: "007AFF"
    )
    .padding()
}

#Preview("Single habit — dark mode") {
    ContributionGraph(
        entries: mockEntries(hex: "AF52DE", seed: 3),
        colorHex: "AF52DE"
    )
    .padding()
    .preferredColorScheme(.dark)
    .background(Color.black)
}

#Preview("All intensity buckets") {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    // Stripe pattern: bucket 0,1,2,3,4 repeating
    var entries: [Date: ContributionEntry] = [:]
    for daysAgo in 0...364 {
        let bucket = (364 - daysAgo) % 5
        let date = cal.date(byAdding: .day, value: -daysAgo, to: today)!
        if bucket > 0 {
            entries[date] = ContributionEntry(intensity: bucket, count: bucket * 2)
        }
    }
    return ContributionGraph(entries: entries, colorHex: "FF9500")
        .padding()
}

#Preview("Multi-habit overview") {
    let layers: [MultiHabitContributionGraph.Layer] = [
        .init(colorHex: "34C759", entries: mockEntries(hex: "34C759", seed: 10)),
        .init(colorHex: "007AFF", entries: mockEntries(hex: "007AFF", seed: 11)),
        .init(colorHex: "AF52DE", entries: mockEntries(hex: "AF52DE", seed: 12)),
    ]
    return VStack {
        Text("Year overview — 3 habits blended").font(.caption).foregroundStyle(.secondary)
        MultiHabitContributionGraph(layers: layers)
    }
    .padding()
}

#Preview("Multi-habit overview — dark") {
    let layers: [MultiHabitContributionGraph.Layer] = [
        .init(colorHex: "FF9500", entries: mockEntries(hex: "FF9500", seed: 20)),
        .init(colorHex: "FF3B30", entries: mockEntries(hex: "FF3B30", seed: 21)),
        .init(colorHex: "FFCC00", entries: mockEntries(hex: "FFCC00", seed: 22)),
    ]
    return MultiHabitContributionGraph(layers: layers)
        .padding()
        .preferredColorScheme(.dark)
        .background(Color.black)
}
#endif
