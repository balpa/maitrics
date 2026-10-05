import Foundation
import UserNotifications
import MaitricsCore

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    /// `UNUserNotificationCenter` crashes without an app bundle (e.g. `swift run`).
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func configure() {
        center?.delegate = self
    }

    func deliver(_ alerts: [UsageAlert]) {
        for alert in alerts {
            post(title: alert.title, body: alert.body)
        }
    }

    func post(title: String, body: String) {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
