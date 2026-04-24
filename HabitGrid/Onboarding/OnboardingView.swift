import SwiftUI

// MARK: - Onboarding page model

private struct OnboardingPage: Identifiable {
    let id: Int
    let systemImage: String
    let imageColor: Color
    let title: String
    let body: String
}

private let pages: [OnboardingPage] = [
    .init(
        id: 0,
        systemImage: "checkmark.circle.fill",
        imageColor: .green,
        title: "Build better habits",
        body: "Track any habit — daily runs, reading, hydration — and watch your streaks grow day by day."
    ),
    .init(
        id: 1,
        systemImage: "chart.bar.fill",
        imageColor: .blue,
        title: "See your progress at a glance",
        body: "HabitGrid's GitHub-style contribution chart gives you a beautiful year-long picture of your consistency."
    ),
    .init(
        id: 2,
        systemImage: "bell.badge.fill",
        imageColor: .orange,
        title: "Gentle reminders",
        body: "Set a reminder for each habit so you never miss a day. Notifications arrive right when you need them."
    ),
]

// MARK: - View

struct OnboardingView: View {

    let onFinish: () -> Void

    @State private var currentPage = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Page tabs
            TabView(selection: $currentPage) {
                ForEach(pages) { page in
                    pageView(page)
                        .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Page indicator + CTA
            VStack(spacing: 20) {
                pageIndicator

                Button(action: advance) {
                    Text(currentPage == pages.count - 1 ? "Get Started" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.primary, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(colorScheme == .dark ? .black : .white)
                }
                .padding(.horizontal, 32)
                .animation(.none, value: currentPage)

                if currentPage < pages.count - 1 {
                    Button("Skip") { onFinish() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 48)
        }
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Page

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(page.imageColor.opacity(0.12))
                    .frame(width: 130, height: 130)
                Image(systemName: page.systemImage)
                    .font(.system(size: 60))
                    .foregroundStyle(page.imageColor)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(page.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - Page indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages) { page in
                Capsule()
                    .fill(currentPage == page.id ? Color.primary : Color(UIColor.systemGray4))
                    .frame(width: currentPage == page.id ? 20 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: currentPage)
            }
        }
    }

    // MARK: - Navigation

    private func advance() {
        if currentPage < pages.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) { currentPage += 1 }
        } else {
            onFinish()
        }
    }
}

#if DEBUG
#Preview {
    OnboardingView(onFinish: {})
}
#endif
