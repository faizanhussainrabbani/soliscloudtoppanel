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
        static let socDayPeaks      = "battery-soc-day-peaks"
        static let voltageDayPeaks  = "battery-voltage-day-peaks"
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

    /// Highest battery SOC seen on each station-local day, keyed "yyyy-MM-dd".
    ///
    /// Exists to answer one question the API cannot: when did the pack last
    /// reach a full charge? LiFePO4 relies on periodically topping out so the
    /// BMS can balance cells and re-anchor its SOC estimate, and this system
    /// rides through roughly five grid outages a day, so the top of charge is
    /// not something that can be assumed.
    ///
    /// Recorded locally because SolisCloud offers no history for it. Every
    /// day-level endpoint tried (`/station/day`, `/inverter/day`,
    /// `/battery/pile/chart` and five siblings) answers 404, so there is
    /// nothing to backfill from and the record necessarily starts at first run
    /// — which is why the UI distinguishes "no full charge" from "not enough
    /// history to say".
    ///
    /// Pruned to `maxRetainedDays` on write. Plain [String: Double] keeps it
    /// plist-native, and 90 dates cost well under 2 KB.
    var socDayPeaks: [String: Double] {
        get { dayPeaks(Key.socDayPeaks) }
        set { setDayPeaks(Key.socDayPeaks, newValue) }
    }

    /// Highest pack voltage seen on each station-local day, keyed the same way.
    ///
    /// The companion to `socDayPeaks`, and the reason the pair exists: the
    /// BMS's SOC is coulomb-counted and can drift to 100% while the pack sits
    /// at the float setpoint, never rising towards absorption — and LFP cells
    /// only balance near the top of the voltage curve. SOC alone therefore
    /// cannot distinguish "topped out and balanced" from "the counter reached
    /// 100". Peak voltage can.
    ///
    /// Sampled from `storageBatteryVoltage` in station/detailMix, so this costs
    /// no extra request. That field is the *inverter's* measurement rather than
    /// the BMS's `batteryVoltage`, deliberately: it is compared against
    /// batteryAcvSet/batteryFcvSet, which are the inverter's own setpoints, and
    /// the two meters read ~0.2 V apart. Same reference frame on both sides.
    var voltageDayPeaks: [String: Double] {
        get { dayPeaks(Key.voltageDayPeaks) }
        set { setDayPeaks(Key.voltageDayPeaks, newValue) }
    }

    private func dayPeaks(_ key: String) -> [String: Double] {
        defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    private func setDayPeaks(_ key: String, _ newValue: [String: Double]) {
        var trimmed = newValue
        if trimmed.count > Self.maxRetainedDays {
            // ISO-8601 dates sort lexically, so dropping the lowest keys drops
            // the oldest days.
            for stale in trimmed.keys.sorted().prefix(trimmed.count - Self.maxRetainedDays) {
                trimmed.removeValue(forKey: stale)
            }
        }
        guard trimmed != dayPeaks(key) else { return }
        objectWillChange.send()
        defaults.set(trimmed, forKey: key)
        changed.send()
    }

    /// Long enough to answer "not in the last three weeks" with room to spare,
    /// short enough that the record never grows without bound.
    private static let maxRetainedDays = 90

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
