import Foundation
import UserNotifications
import AppKit

/// Equivalent of GNOME's Main.notify().
///
/// UNUserNotificationCenter needs the process to be a LaunchServices-registered
/// bundle; an ad-hoc-signed app run from a build directory can fail to register.
/// When that happens we fall back to `osascript display notification` so the
/// grid-outage alert still fires.
@MainActor
final class Notifier {
    static let shared = Notifier()

    private var useUserNotifications = false
    private var didRequestAuthorization = false

    private init() {}

    func prepare() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true

        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("SolisSolarMonitor: no bundle identifier — using osascript notifications")
            return
        }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in
                if let error {
                    NSLog("SolisSolarMonitor: notification authorization failed (\(error.localizedDescription)) — using osascript fallback")
                    self.useUserNotifications = false
                } else {
                    self.useUserNotifications = granted
                }
            }
        }
    }

    func notify(title: String, body: String) {
        // Which delivery path was taken is otherwise invisible: success is
        // silent on both, and a denied authorization downgrades to osascript
        // without any error. Worth one line — a notification that never
        // arrives is indistinguishable from one that was never requested.
        NSLog("%@", "SolisSolarMonitor: notify via \(useUserNotifications ? "UNUserNotificationCenter" : "osascript") — \(title)")

        if useUserNotifications {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    NSLog("SolisSolarMonitor: notification delivery failed — \(error.localizedDescription)")
                    Task { @MainActor in self.notifyViaOSAScript(title: title, body: body) }
                }
            }
        } else {
            notifyViaOSAScript(title: title, body: body)
        }
    }

    private func notifyViaOSAScript(title: String, body: String) {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
        }
        let script = "display notification \"\(escape(body))\" with title \"\(escape(title))\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
        } catch {
            NSLog("SolisSolarMonitor: osascript notification failed — \(error.localizedDescription)")
        }
    }
}
