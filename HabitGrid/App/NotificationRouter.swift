import Foundation
import UserNotifications

// MARK: - Router

/// Holds the medication UUID surfaced when a medication notification is tapped.
/// Injected via @Environment; ContentView reacts by switching to Today and
/// MedicationTodaySection opens the LogTakenSheet automatically.
@Observable
final class NotificationRouter {
    var pendingMedicationID: UUID?
}

// MARK: - Delegate

/// Bridges UNUserNotificationCenter callbacks onto the main actor so the router
/// can be mutated safely from the notification tap handler.
final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    let router: NotificationRouter

    init(router: NotificationRouter) {
        self.router = router
    }

    /// Called when the user taps a notification while the app is in the background / killed.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let idStr = info["medicationID"] as? String, let id = UUID(uuidString: idStr) {
            Task { @MainActor in self.router.pendingMedicationID = id }
        }
        completionHandler()
    }

    /// Show banners and play sound when a notification arrives while the app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
