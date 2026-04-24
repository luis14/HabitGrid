import SwiftUI

struct InfoView: View {

    var body: some View {
        NavigationStack {
            List {
                appHeader
                featuresSection
                usageSection
                privacySection
            }
            .navigationTitle("Info")
        }
    }

    // MARK: - App header

    private var appHeader: some View {
        Section {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "34C759"), Color(hex: "007AFF")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 88, height: 88)
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                Text("HabitGrid")
                    .font(.title2.weight(.bold))
                Text("Build habits. See your progress.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Version 1.0")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        Section("Features") {
            featureRow("square.grid.3x3.fill",  .green,  "Contribution Heatmap",
                       "GitHub-style grid shows every day at a glance")
            featureRow("flame.fill",             .orange, "Streak Tracking",
                       "Daily and weekly streaks with archive awareness")
            featureRow("heart.fill",             .red,    "Mood Logging",
                       "Quick daily check-in with optional notes")
            featureRow("chart.bar.fill",         .blue,   "Analytics",
                       "Weekday breakdown and completion rates")
            featureRow("bell.fill",              .purple, "Reminders",
                       "Local notifications, no account required")
        }
    }

    // MARK: - Usage tips

    private var usageSection: some View {
        Section("Tips") {
            tipRow("Swipe left on a habit to delete it")
            tipRow("Swipe right on a habit to edit it")
            tipRow("Long-press a habit for more options")
            tipRow("Tap the circle on any row to log a quick completion")
            tipRow("Long-press the Today card to log count + note")
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section("Privacy") {
            VStack(alignment: .leading, spacing: 6) {
                Label("All data is stored on-device", systemImage: "lock.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("HabitGrid uses SwiftData with no iCloud sync and no network requests. Your habits never leave your device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func featureRow(_ icon: String, _ color: Color, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func tipRow(_ text: String) -> some View {
        Label(text, systemImage: "lightbulb")
            .font(.subheadline)
            .foregroundStyle(.primary)
            .symbolRenderingMode(.hierarchical)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    InfoView()
}
#endif
