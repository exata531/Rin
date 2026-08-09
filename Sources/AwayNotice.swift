// the bell reaching a person who is not at the mac
// off by default because silent-in-class is the whole personality of the bell

import AppKit
import UserNotifications

/// The optional Notification Center route for the bell. At the Mac the bell
/// is a dot and a trackpad tap, which is exactly right there and invisible
/// from anywhere else; this closes the away gap for people who want it
/// closed. Off by default, and the at-Mac behaviour never changes: a session
/// can still never go off in the middle of class.
enum AwayNotice {
    private static let key = "notifyWhenAway"
    private static let identifier = "rin-attention"

    /// Tapping the notification should land in the panel; wired by the app
    /// delegate, which is the only thing that can open it.
    static var openPanel: () -> Void = {}

    static var isEnabled: Bool {
        get { AppConfig.defaults.bool(forKey: key) }
        set {
            AppConfig.defaults.set(newValue, forKey: key)
            guard newValue else { return }
            // Permission follows intent: macOS is asked at the moment of
            // opting in, never at launch for a feature that is off. And the
            // one dishonest state a switch can hold is ON while the system
            // refuses to deliver, so the answer is read rather than assumed.
            let center = UNUserNotificationCenter.current()
            center.getNotificationSettings { settings in
                DispatchQueue.main.async {
                    switch settings.authorizationStatus {
                    case .notDetermined:
                        center.requestAuthorization(options: [.alert]) { granted, _ in
                            // "Don't Allow" on the system's own ask is an
                            // answer, not a misunderstanding: the switch
                            // follows it quietly instead of lying on.
                            guard !granted else { return }
                            DispatchQueue.main.async {
                                AppConfig.defaults.set(false, forKey: key)
                            }
                        }
                    case .denied:
                        // Blocked by an older decision the person may not
                        // remember making: say so once, and point at the
                        // switch that actually decides.
                        explainDenied()
                    default:
                        break
                    }
                }
            }
            activate()
        }
    }

    private static func explainDenied() {
        let alert = NSAlert()
        alert.messageText = "macOS is blocking Rin's notifications"
        alert.informativeText = """
            Notify When Away is on, but notifications from Rin are switched \
            off in System Settings, so nothing will arrive. Allow Rin under \
            Notifications to close the gap.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// The summons was answered: the panel is open, so an unread banner is
    /// stale mail. Guarded on the switch, like everything here, so the
    /// notification center is never touched for people who never opted in.
    static func clear() {
        guard isEnabled else { return }
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    /// Take the delegate seat, only when the feature is actually on: the
    /// notification center is never touched for people who never opted in.
    static func activate() {
        guard isEnabled else { return }
        UNUserNotificationCenter.current().delegate = tap
    }

    /// One notification, replacing any unread one: two "wants you" is a
    /// pile, and a pile is Notification Center's problem, not a summons.
    static func post(title: String) {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rin"
        content.body = title
        let request = UNNotificationRequest(
            identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static let tap = NoticeTap()

    private final class NoticeTap: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            DispatchQueue.main.async { AwayNotice.openPanel() }
            completionHandler()
        }
    }
}
