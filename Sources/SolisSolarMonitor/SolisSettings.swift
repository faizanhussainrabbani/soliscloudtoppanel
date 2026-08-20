import Foundation
import Combine

/// Direct port of org.gnome.shell.extensions.solis-solar-monitor.gschema.xml.
/// GSettings -> UserDefaults, key-for-key, including the shipped defaults.
@MainActor
final class SolisSettings: ObservableObject {
    static let shared = SolisSettings()

    private let defaults = UserDefaults.standard

    // Emitted on any change, mirroring GSettings' single `changed` signal
    // that the extension connects to in enable().
    let changed = PassthroughSubject<Void, Never>()

    private enum Key {
        static let stationID        = "station-id"
        static let authorization    = "authorization"
        static let cookie           = "cookie"
        static let deviceID         = "device-id"
        static let refreshInterval  = "refresh-interval"
        static let panelDisplayMode = "panel-display-mode"
        static let batteryCapacity  = "battery-capacity-kwh"
        static let batteryReserve   = "battery-reserve-soc"
        static let signingSecret    = "api-signing-secret"
    }

    private init() {
        // Nothing account-specific ships in source.
        //
        // These used to carry a live session — cookie, authorization header,
        // device-id and station ID — which meant a clone of this repository
        // was a working login to one particular SolisCloud account, and a
        // screenshot of the Preferences window published it. The real values
        // live in UserDefaults, written by the WKWebView sign-in, which is
        // where they belonged all along; the hardcoded copies were only ever
        // fallbacks that the running app never read.
        //
        // Two values have no sign-in flow to capture them and must be set by
        // hand once, on the machine that runs the app:
        //
        //   defaults write com.faizan.SolisSolarMonitor station-id -string '…'
        //   defaults write com.faizan.SolisSolarMonitor api-signing-secret -string '…'
        //
        // content-md5 was also shipped here and is simply gone: it is an MD5 of
        // each request body, recomputed per call by SolisAPI.computeAuth, so a
        // stored one could never have been correct for anything.
        defaults.register(defaults: [
            Key.refreshInterval: 60,
            Key.panelDisplayMode: "compact",
        ])
    }

    private func setString(_ key: String, _ value: String) {
        guard defaults.string(forKey: key) != value else { return }
        objectWillChange.send()
        defaults.set(value, forKey: key)
        changed.send()
    }

    var stationID: String {
        get { defaults.string(forKey: Key.stationID) ?? "" }
        set { setString(Key.stationID, newValue) }
    }

    var authorization: String {
        get { defaults.string(forKey: Key.authorization) ?? "" }
        set { setString(Key.authorization, newValue) }
    }

    var cookie: String {
        get { defaults.string(forKey: Key.cookie) ?? "" }
        set { setString(Key.cookie, newValue) }
    }

    var deviceID: String {
        get { defaults.string(forKey: Key.deviceID) ?? "" }
        set { setString(Key.deviceID, newValue) }
    }

    /// Clamped to the same 10–3600 range the prefs SpinRow enforces.
    var refreshInterval: Int {
        get { defaults.integer(forKey: Key.refreshInterval) }
        set {
            let clamped = min(3600, max(10, newValue))
            guard defaults.integer(forKey: Key.refreshInterval) != clamped else { return }
            objectWillChange.send()
            defaults.set(clamped, forKey: Key.refreshInterval)
            changed.send()
        }
    }

    /// One of "compact", "full", "minimal" — the three the gschema defines —
    /// or "adaptive", which is a macOS-side addition (see SolisMonitor's
    /// adaptive panel section). Default stays "compact" for parity; adaptive
    /// is opt-in.
    var panelDisplayMode: String {
        get { defaults.string(forKey: Key.panelDisplayMode) ?? "compact" }
        set { setString(Key.panelDisplayMode, newValue) }
    }

    /// SolisCloud's request-signing secret. Deliberately absent from source —
    /// see SolisAPI. Empty means the app cannot sign anything, which callers
    /// report as a configuration problem rather than an expired session.
    var signingSecret: String {
        get { defaults.string(forKey: Key.signingSecret) ?? "" }
        set { setString(Key.signingSecret, newValue) }
    }

    /// Hidden diagnostic with no UI, read fresh on every poll:
    ///
    ///   defaults write com.faizan.SolisSolarMonitor panel-debug-tick -bool true
    ///
    /// Appends an incrementing poll counter to the panel text. This exists
    /// because the menu bar cannot be read from outside the process (no screen
    /// recording, no assistive access), and SolisCloud's upstream reading only
    /// changes every few minutes — so "the panel didn't change" is normally
    /// ambiguous between a stale data source and a label that isn't
    /// re-rendering. A counter that moves on every poll separates the two.
    var panelDebugTick: Bool {
        defaults.bool(forKey: "panel-debug-tick")
    }

    /// Usable battery capacity in kWh, for the time-remaining estimate.
    ///
    /// This has to be a setting because SolisCloud doesn't report it. Checked
    /// against a live response: `batteryCapacityEnergy` is 0, and `capacity`
    /// (6.45) is the PV array in kWp, not the battery. 0 means "not set" and
    /// suppresses the estimate rather than inventing one.
    var batteryCapacityKWh: Double {
        get { defaults.double(forKey: Key.batteryCapacity) }
        set {
            let clamped = min(200, max(0, newValue))
            guard defaults.double(forKey: Key.batteryCapacity) != clamped else { return }
            objectWillChange.send()
            defaults.set(clamped, forKey: Key.batteryCapacity)
            changed.send()
        }
    }

    /// The state of charge the inverter stops discharging at, as a percentage.
    ///
    /// Without this the time-remaining estimate divides the whole battery by
    /// the current draw and overstates the answer badly — a bank that stops at
    /// 25% has only three quarters of its nominal energy available, so at 54%
    /// the usable share is 29 points, not 54.
    ///
    /// Defaults to 0 rather than a typical-looking 20: a wrong reserve produces
    /// a confidently wrong runtime, and there is no way to detect the real one
    /// from the API.
    var batteryReserveSOC: Double {
        get { defaults.double(forKey: Key.batteryReserve) }
        set {
            let clamped = min(95, max(0, newValue))
            guard defaults.double(forKey: Key.batteryReserve) != clamped else { return }
            objectWillChange.send()
            defaults.set(clamped, forKey: Key.batteryReserve)
            changed.send()
        }
    }
}
