import SwiftUI
import AppKit

@main
struct SolisSolarMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var monitor = SolisMonitor.shared
    @StateObject private var settings = SolisSettings.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor, settings: settings)
        } label: {
            // Equivalent of the St.Label in the GNOME top bar.
            //
            // SETTLED, THE HARD WAY — do not try SF Symbols here again without
            // changing the mechanism. The window uses SF Symbols and the menu
            // bar uses emoji, and closing that gap was attempted twice:
            //
            //   1. HStack + ForEach over icon/text segments. MenuBarExtra does
            //      not expand view hierarchies in its label — only the first
            //      segment drew, and the battery vanished from the menu bar.
            //   2. A single Text with Image(systemName:) interpolated into it,
            //      built by concatenation. The label rendered "0.83 kW  43%":
            //      the text survived, every image was silently dropped.
            //
            // The fix is the third option: an *Image* label is supported, so
            // the whole panel — symbols and numbers — is laid out as an
            // ordinary SwiftUI view offscreen and rendered to a template
            // NSImage. See SolisMonitor.renderPanelImage.
            //
            // Text(panelText) remains the fallback for the moment before the
            // first render, and for any case where rendering fails: a label
            // that draws nothing would take the app's only click target with
            // it.
            if let image = monitor.panelImage {
                Image(nsImage: image)
            } else {
                Text(monitor.panelText)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon — the menu bar item is the whole UI.
        NSApp.setActivationPolicy(.accessory)

        MainActor.assumeIsolated {
            Notifier.shared.prepare()
            SolisMonitor.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            SolisMonitor.shared.stop()
        }
    }
}
