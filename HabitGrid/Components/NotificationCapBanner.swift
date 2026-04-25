import SwiftUI

// MARK: - Banner state

/// Shared state that NotificationService writes to and ContentView reads from.
@Observable @MainActor
final class NotificationCapBannerState {

    static let shared = NotificationCapBannerState()
    private init() {}

    private(set) var droppedNames: [String] = []
    private(set) var isVisible: Bool = false

    private var dismissTask: Task<Void, Never>?

    func report(droppedNames names: [String]) {
        guard !names.isEmpty else { return }
        droppedNames = names
        isVisible = true
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(6))
            dismiss()
        }
    }

    func dismiss() {
        isVisible = false
        droppedNames = []
    }
}

// MARK: - Banner view

/// Slide-in banner displayed at the top of the screen when notifications
/// are dropped because the iOS 64-request cap (minus buffer) is reached.
struct NotificationCapBanner: View {

    @State private var state = NotificationCapBannerState.shared

    var body: some View {
        if state.isVisible {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bell.badge.slash.fill")
                        .font(.title3)
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Reminder limit reached")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(bannerMessage)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(3)
                    }

                    Spacer(minLength: 0)

                    Button { state.dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(999)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.isVisible)
        }
    }

    private var bannerMessage: String {
        let names = state.droppedNames
        switch names.count {
        case 1:
            return "\"\(names[0])\" lost its reminder slot. iOS allows 60 active reminders. Remove unused reminders to free up slots."
        case 2:
            return "\"\(names[0])\" and \"\(names[1])\" lost their reminder slots. Remove unused reminders to free up slots."
        default:
            let first = names.prefix(2).joined(separator: ", ")
            return "\(first) and \(names.count - 2) more lost their reminder slots. iOS allows 60 active reminders."
        }
    }
}
