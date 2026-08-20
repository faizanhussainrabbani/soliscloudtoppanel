import SwiftUI
import AppKit

/// Port of SolisPreferences.fillPreferencesWindow() from prefs.js.
/// Adw.PreferencesPage -> TabView tab, Adw.PreferencesGroup -> GroupBox,
/// Adw.ActionRow / EntryRow / SpinRow / ComboRow / SwitchRow -> their
/// closest AppKit-native SwiftUI equivalents.
struct PreferencesView: View {
    @ObservedObject var settings: SolisSettings

    var body: some View {
        TabView {
            setupPage
                .tabItem { Label("Setup", systemImage: "lock.display") }
            displayPage
                .tabItem { Label("Display", systemImage: "menubar.rectangle") }
        }
        // Width fixed, height free. Both tabs previously inherited Setup's
        // 560pt, which left the Display tab with a third of the window empty.
        .frame(width: 560)
        .frame(minHeight: 300)
    }

    // MARK: - Page 1: Setup & Login

    /// Revealed only on request. Three reasons, and the first is the one that
    /// matters: these fields hold a working session, and a casual screenshot of
    /// this window used to publish it. Second, they duplicated the read-only
    /// status list above them — the same four values twice, once truncated and
    /// once not, which is the duplication the main window spent a long time
    /// shedding. Third, almost nobody needs them: logging in fills them in.
    @State private var showCredentialFields = false

    private var setupPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        // One instruction, once. There were previously two
                        // sentences saying the same thing, one under the other.
                        Text("Log in and open your station page. The app captures what it needs automatically.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            // The green seal used to appear alone, with colour
                            // carrying the whole message. It says what it means
                            // now, and the not-connected case says so too
                            // rather than being an absence.
                            Image(systemName: connected ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(connected ? Color.solisOnline : Color.solisWarning)
                            Text(connected ? "Signed in" : "Not signed in")
                                .font(.system(size: 11))
                                .foregroundStyle(connected ? Color.solisOnline : Color.solisWarning)
                            Spacer()
                            Button(connected ? "Sign In Again" : "Sign In") {
                                LoginWindowController.show(parent: PreferencesWindow.window)
                            }
                        }

                        if connected {
                            Divider()
                            StatusRow(title: "Station", value: settings.stationID, truncate: false)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                } label: {
                    Text("SolisCloud Account").bold()
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show saved credentials", isOn: $showCredentialFields)
                            .font(.system(size: 11))

                        Text("Only needed if signing in didn't work. These values are a live session — treat them like a password.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if showCredentialFields {
                            Divider()
                            // Plain names, not header names. Someone opening
                            // this has a "it stopped working" problem, not a
                            // Content-MD5 problem.
                            EntryRow(title: "Station ID", text: bind(\.stationID))
                            EntryRow(title: "Authorization", text: bind(\.authorization))
                            EntryRow(title: "Device ID", text: bind(\.deviceID))
                            EntryRow(title: "Session cookie", text: bind(\.cookie))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                } label: {
                    Text("Advanced").bold()
                }
            }
            .padding(20)
        }
    }

    private var connected: Bool {
        !settings.authorization.isEmpty && !settings.cookie.isEmpty
    }

    // MARK: - Page 2: Display & Polling

    private var displayPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Configure panel text appearance and polling frequency")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        // Refresh Interval — matches the 10–3600 s SpinRow
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Refresh Interval (seconds)")
                                Spacer()
                                Stepper(
                                    value: Binding(
                                        get: { settings.refreshInterval },
                                        set: { settings.refreshInterval = $0 }
                                    ),
                                    in: 10...3600,
                                    step: 10
                                ) {
                                    Text("\(settings.refreshInterval)")
                                        .monospacedDigit()
                                        .frame(minWidth: 44, alignment: .trailing)
                                }
                            }
                            Text("Frequency of SolisCloud background data updates (10 – 3600 s)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        // Panel Display Mode
                        VStack(alignment: .leading, spacing: 4) {
                            Picker("Top Panel Display Format", selection: Binding(
                                get: { settings.panelDisplayMode },
                                set: { settings.panelDisplayMode = $0 }
                            )) {
                                // Short enough to survive the popup's width —
                                // the old Adaptive label was cut off mid-value
                                // — and without emoji, which the menu bar
                                // stopped using when it moved to SF Symbols.
                                Text("Adaptive — follows conditions").tag("adaptive")
                                Text("Compact — solar and battery").tag("compact")
                                Text("Full — solar, home and battery").tag("full")
                                Text("Minimal — solar only").tag("minimal")
                            }
                            // Only Adaptive needs explaining — the other three
                            // are self-evident from their own labels.
                            Text("Adaptive swaps Solar for Home Load once solar goes quiet at night, and swaps Battery for Grid when the battery is low and not currently supplying the house")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Divider()

                        // Battery capacity — needed for the time-remaining
                        // estimate. SolisCloud doesn't report it (checked
                        // live: batteryCapacityEnergy is 0, and `capacity` is
                        // the PV array in kWp), so it has to be entered.
                        VStack(alignment: .leading, spacing: 4) {
                            // The units differ in width ("kWh" vs "%"), so a
                            // trailing Spacer left the two boxes at different
                            // x positions. Fixing the unit column instead keeps
                            // the fields aligned with each other.
                            NumberRow(title: "Battery capacity", unit: "kWh",
                                      value: Binding(
                                        get: { settings.batteryCapacityKWh },
                                        set: { settings.batteryCapacityKWh = $0 }),
                                      decimals: 2)
                            // The discharge cut-off used to be typed here. The
                            // inverter reports it (socDischargeSet), and it read
                            // 15% where this field said 25 — so the setting was
                            // both redundant and wrong. The stored value stays
                            // as a fallback for a response that omits it.
                            Text("Total capacity of your battery bank when new. Time remaining accounts for the pack's reported health and the cut-off your inverter is configured with. Leave at 0 to hide the estimate.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                } label: {
                    Text("Display & Update Options").bold()
                }
            }
            .padding(20)
        }
    }

    private func bind(_ keyPath: ReferenceWritableKeyPath<SolisSettings, String>) -> Binding<String> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }
}

/// Adw.ActionRow with a dimmed, truncated value suffix.
private struct StatusRow: View {
    let title: String
    let value: String
    var truncate: Bool = true

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(displayValue)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var displayValue: String {
        guard !value.isEmpty else { return "Not set" }
        guard truncate, value.count > 28 else { return value }
        return String(value.prefix(28)) + "…"
    }
}

/// Adw.EntryRow.
private struct EntryRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
        }
    }
}

// MARK: - Window host

/// The app runs as an accessory (no Dock icon), so the preferences window is
/// managed directly rather than through SwiftUI's Settings scene.
@MainActor
enum PreferencesWindow {
    private(set) static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            // Shorter than the old 560: with the credential fields now behind
            // a disclosure, Setup no longer needs that much room, and the
            // window is resizable for the case where they're revealed.
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Solis Solar Monitor Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: PreferencesView(settings: SolisSettings.shared)
        )
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// A right-aligned number field with a unit, in a fixed-width column so that
/// stacked rows line up whatever their units are.
private struct NumberRow: View {
    let title: String
    let unit: String
    @Binding var value: Double
    let decimals: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: $value,
                      format: .number.precision(.fractionLength(0...decimals)))
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
        }
    }
}
