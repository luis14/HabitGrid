import SwiftUI

// MARK: - Shared habit icon (SF Symbol or legacy emoji)

/// Renders a habit icon that may be either an SF Symbol name (ASCII) or a legacy emoji string.
struct HabitSymbolView: View {
    let symbol: String
    let color: Color
    let size: Font

    init(_ symbol: String, color: Color = .primary, size: Font = .title3) {
        self.symbol = symbol
        self.color  = color
        self.size   = size
    }

    var body: some View {
        Group {
            if symbol.unicodeScalars.allSatisfy({ $0.value < 128 }) {
                Image(systemName: symbol)
                    .font(size)
                    .foregroundStyle(color)
            } else {
                Text(symbol).font(size)
            }
        }
    }
}

// MARK: - HabitCard

/// A tappable card representing a single habit on the Today screen.
///
/// - Tap: toggle completion (binary) or increment count (multi).
/// - Long press: opens the partial-completion / note sheet.
struct HabitCard: View {

    let habit: Habit
    let completionCount: Int
    let streak: Int
    let onTap: () -> Void
    let onLongPress: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isComplete: Bool { completionCount >= habit.targetCount }
    private var habitColor: Color { Color(hex: habit.colorHex) }

    var body: some View {
        HStack(spacing: 14) {
            emojiBadge
            content
            Spacer(minLength: 0)
            completionIndicator
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(cardBorder)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.4, perform: onLongPress)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isComplete)
        .animation(.easeInOut(duration: 0.2), value: completionCount)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double-tap to toggle, hold for options")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Sub-views

    private var emojiBadge: some View {
        ZStack {
            Circle()
                .fill(habitColor.opacity(isComplete ? 0.22 : 0.12))
                .frame(width: 46, height: 46)
            HabitSymbolView(habit.emoji, color: habitColor, size: .title2)
                .opacity(isComplete ? 0.7 : 1.0)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(habit.name)
                .font(.body.weight(.medium))
                .foregroundStyle(isComplete ? .secondary : .primary)
                .strikethrough(isComplete, color: .secondary)
                .lineLimit(1)

            Group {
                if habit.targetCount > 1 {
                    multiCountRow
                } else {
                    streakRow
                }
            }
        }
    }

    private var multiCountRow: some View {
        HStack(spacing: 8) {
            Text("\(completionCount) / \(habit.targetCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(isComplete ? habitColor : .secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(UIColor.systemGray5))
                        .frame(height: 4)
                    Capsule()
                        .fill(habitColor)
                        .frame(
                            width: geo.size.width * min(1, Double(completionCount) / Double(habit.targetCount)),
                            height: 4
                        )
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: completionCount)
                }
            }
            .frame(height: 4)
        }
    }

    private var streakRow: some View {
        Group {
            if streak > 1 {
                Label("\(streak) day streak", systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if streak == 1 {
                Label("1 day streak", systemImage: "flame")
                    .font(.caption)
                    .foregroundStyle(.orange.opacity(0.7))
            } else {
                Text(habit.schedule.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var completionIndicator: some View {
        ZStack {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(habitColor)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundStyle(Color(UIColor.systemGray3))
            }
        }
        .frame(width: 30, height: 30)
    }

    private var cardBackground: some ShapeStyle {
        if isComplete {
            return AnyShapeStyle(habitColor.opacity(colorScheme == .dark ? 0.12 : 0.07))
        }
        return AnyShapeStyle(Color(UIColor.secondarySystemBackground))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(
                isComplete ? habitColor.opacity(0.35) : Color.clear,
                lineWidth: 1
            )
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var parts = [habit.name]
        if habit.targetCount > 1 {
            parts.append("\(completionCount) of \(habit.targetCount)")
        }
        parts.append(isComplete ? "complete" : "incomplete")
        if streak > 0 { parts.append("\(streak) day streak") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("HabitCard states") {
    let habit = Habit(name: "Morning Run", emoji: "🏃", colorHex: "34C759", targetCount: 1)
    let multi = Habit(name: "Water", emoji: "💧", colorHex: "5AC8FA", targetCount: 8)
    return ScrollView {
        VStack(spacing: 10) {
            HabitCard(habit: habit, completionCount: 0, streak: 0,
                      onTap: {}, onLongPress: {})
            HabitCard(habit: habit, completionCount: 1, streak: 7,
                      onTap: {}, onLongPress: {})
            HabitCard(habit: multi, completionCount: 3, streak: 4,
                      onTap: {}, onLongPress: {})
            HabitCard(habit: multi, completionCount: 8, streak: 21,
                      onTap: {}, onLongPress: {})
        }
        .padding()
    }
}
#endif
