import Foundation
import Combine
import SwiftUI
import AppKit

/// Every label the GNOME popup renders, with the same initial strings
/// _buildPopupMenu() seeds them with.
struct DisplayState {
    var stationTitle    = "Solis System"
    var timestamp       = "Last Update: Never"
    var badgeText       = "Updating"
    var badgeOnline     = true

    // --- Hero summary (design direction A: one number leads) ---------------
    // The window's dominant reading, chosen the same way the menu bar chooses
    // its first slot — so the two can never disagree about what matters now.
    var statusLine      = "Solis · connecting…"
    /// Drives the status dot and, when false, surfaces badgeText as words.
    var statusOK        = true
    /// The inverter hasn't reported for a while, even though our own fetch
    /// succeeded. These are different failures and the app used to conflate
    /// them: a logger knocked offline by a home internet outage leaves
    /// SolisCloud serving its last reading indefinitely, and every number here
    /// then looks live when it is hours old.
    var dataStale       = false
    /// "No update for 25 min" — only set while dataStale.
    var dataAgeText: String?
    var heroLabel       = "Solar Output"
    var heroValue       = "0.00"
    var heroUnit        = "kW"
    /// One plain-language sentence replacing the four per-row subtitles.
    var heroCaption     = "Waiting for the first reading"
    /// Which metric the hero is showing; the stat strip shows the other three.
    var heroIsSolar     = true

    var pvPower         = "0.00 kW"

    var batterySOC      = "0%"
    /// 🔋 normally, 🪫 below the low-battery level. Emoji, because the menu bar
    /// label is a plain String and can't hold an SF Symbol. Computed once per
    /// poll in updateUI so nothing can disagree about it.
    var batteryIcon     = "🔋"
    /// The same state as an SF Symbol, for the window and the rendered menu
    /// bar label. Steps with the charge level, which the 🔋/🪫 pair can't.
    var batterySymbol   = "battery.100percent"
    /// Drives the one piece of semantic colour in the summary.
    var batteryLow      = false
    /// Adds a small bolt beside the battery glyph, in the window and the menu
    /// bar alike — the level symbol can't carry charging on its own.
    var batteryCharging = false

    var loadPower       = "0.00 kW"
    var gridPower       = "0.00 kW"

    // --- Supporting facts (the Details section) ----------------------------
    // Details used to restate the same four readings the hero and the tiles
    // already show — four values, eight places. These are the facts the
    // summary can't carry, so opening Details adds information instead of
    // repeating it. Nothing here duplicates a value above.
    var solarTodayText      = "—"
    /// Total house consumption today. The most basic figure in a home energy
    /// app and absent for weeks — the old subsystem grouping (solar / grid /
    /// battery) had nowhere obvious to put it, so nobody noticed it missing.
    /// Grouping by time horizon made the hole visible immediately.
    var usedTodayText       = "—"
    var usedTodayZero       = true
    var gridBoughtTodayText = "—"
    /// What today's grid import cost. Replaced "Sold to grid today", which is
    /// permanently 0 without net metering — a row that can only ever say zero
    /// is a row that isn't earning its place.
    var gridCostTodayText   = "—"
    /// "Sunset" / "Sunrise" and the time, whichever is next. nil if the
    /// station's coordinates are missing or the sun doesn't set here today.
    var sunLabel            = "Sunset"
    var sunTimeText: String?
    /// Today's best three hours for production, from the weather forecast.
    ///
    /// Three states: upcoming ("12:00 – 15:00"), underway ("Now, until 15:00"),
    /// and over — in which case this is nil and the row disappears. A window
    /// that has passed is history, and the row was reporting it as though it
    /// were a plan.
    var peakWindowText: String?
    var peakWindowLabel     = "Peak window today"
    /// Underway right now, so the icon lights up like every other live metric.
    var peakWindowLive      = false
    /// "3% above last week" — today's forecast sun against recent days.
    /// Shown while the sun is up; after dark the generation-based
    /// solarComparisonText takes over, so the day's prospect gives way to the
    /// day's result rather than both sitting there at once.
    var sunTodayComparison: String?
    var batteryFlowText     = "Idle"
    /// The duration, for the hero caption: "about 1 h 55 m left".
    ///
    /// nil when the answer would be a guess — no capacity configured, battery
    /// idle, or a runtime long enough to be meaningless.
    var batteryTimeText: String?
    /// The same estimate as a clock time, for the Details row: "01:10".
    ///
    /// Deliberately a different framing rather than a second copy of the
    /// duration. "How long have I got" and "when does it run out" are
    /// different questions, and printing one answer twice was the exact defect
    /// this section was restructured to remove.
    var batteryEndTimeText: String?
    /// "On battery until" or "Full at" — the row's label moves with the
    /// direction, so the value can be a bare time.
    var batteryEndLabel     = "On battery until"
    /// Separates "no estimate because you haven't told me the capacity" from
    /// "no estimate because nothing is flowing". The row used to show the
    /// capacity prompt for both, which read as an error on a correctly
    /// configured app whenever the battery was simply idle.
    var batteryCapacityUnset = true
    /// nil on the first of the month, or when the API's period units don't
    /// match — see solarComparison.
    var solarComparisonText: String?
    // --- "Dim what isn't happening" ----------------------------------------
    //
    // One rule, applied everywhere: an icon is dimmed when the thing it stands
    // for is at zero. Colour then means "this is live", which is information,
    // instead of "this is the solar one", which the label already says.
    //
    // Each flag is about its own row's value, deliberately. The first version
    // dimmed the Solar *today* icon from `solarAsleep` — whether the sun is
    // producing this instant — which is the wrong question for a daily total:
    // after a sunny day the row would read "12 kWh" in grey all evening.

    /// Current solar output is below the noise floor.
    var solarAsleep         = true
    /// Today's generation is still zero — a different fact from solarAsleep.
    var solarTodayZero      = true
    /// No meaningful import or export.
    var gridIdle            = true
    /// Nothing bought from the grid yet today.
    var gridBoughtZero      = true
    /// Neither charging nor discharging.
    var batteryIdle         = true
    /// The house is drawing essentially nothing.
    var loadIdle            = true

    // --- Alarms, from /alarm/list ------------------------------------------
    //
    // Replaces everything that used to be inferred from `data.state`. Measured
    // during a real grid outage, `state` read 3 (identical to a healthy dusk
    // reading the day before) and `alarmCount` read 0, while the alarm endpoint
    // returned code 1015 "NO-Grid". Both of the fields this app previously
    // trusted were wrong at the same moment.

    /// "41 °C", or with the limit named once it's running hot.
    var inverterTempText: String?
    /// Near the documented 110 °C internal shutdown.
    var inverterTempHot      = false

    /// "Grid outage" / "NO-Grid" — the headline for the warning row.
    var alarmSummary: String?
    /// "Since 18:33" — begin time, for the Details row.
    var alarmDetail: String?
    /// A grid-loss alarm specifically, which deserves plainer wording than the
    /// inverter's own terse code.
    var gridOutage          = false
}

/// One icon+text pair used to assemble the menu bar string.
///
/// The `symbol` is an SF Symbol name and is currently only used to pick the
/// matching emoji: MenuBarExtra's label silently drops images (see SolisApp).
/// It stays because the segments are how the panel string is composed, and
/// because it is what a future NSStatusItem-based label would render directly.
struct PanelSegment {
    let symbol: String?
    /// A smaller glyph drawn tight against `symbol`.
    ///
    /// Exists because SF Symbols has no battery-level-with-bolt beyond
    /// `battery.100percent.bolt`, so charging can't be folded into the level
    /// symbol without drawing a full battery next to the text "54%". Two
    /// glyphs say both things truthfully.
    var accessorySymbol: String? = nil
    let text: String
}

/// Port of the SolisSolarExtension class from extension.js.
@MainActor
final class SolisMonitor: ObservableObject {
    static let shared = SolisMonitor()

    @Published private(set) var panelText = "Loading..."
    /// The panel drawn to an image, so the menu bar can show SF Symbols.
    ///
    /// MenuBarExtra's label silently drops Image views — both from a container
    /// and from inside a Text — and Apple's position on styling it is that you
    /// can't, because the OS owns it. An Image label *is* supported, though, so
    /// the whole label is laid out as a normal SwiftUI view offscreen and
    /// rendered to one. See renderPanelImage.
    @Published private(set) var panelImage: NSImage?
    @Published private(set) var display = DisplayState()
    @Published private(set) var sessionExpired = false

    private let settings = SolisSettings.shared
    private var timer: Timer?
    private var settingsObserver: AnyCancellable?
    private var refetchWorkItem: DispatchWorkItem?

    // Adaptive panel mode state. Which metric each of the two panel slots is
    // currently showing, plus the consecutive-poll counters that keep them
    // from flipping on every reading. See updateAdaptiveSlots.
    private var adaptiveShowingLoad = false
    private var adaptiveShowingGrid = false
    private var solarSlotPendingPolls = 0
    private var gridSlotPendingPolls = 0
    private var adaptiveSeeded = false

    /// Successful polls since launch. Only used by the panel-debug-tick
    /// diagnostic and the log line.
    private var pollCount = 0

    // Today's forecast peak window. Held here rather than in DisplayState
    // because DisplayState is rebuilt from scratch on every poll, and this
    // arrives on its own schedule from a different service.
    private var peakWindow: SolarForecast.Window?
    private var tomorrowPeakWindow: SolarForecast.Window?
    private var sunTodayComparison: String?
    private var peakWindowFetchedAt: Date?
    /// Whether the sun is currently up, from the computed sun times.
    private var isDaytime = false
    /// Set from the computed sun times each poll, before anything reads it.
    private var afterSunset = false

    /// Alarm codes seen on the previous poll, so a notification fires on the
    /// transition rather than on every poll while an alarm persists.
    private var inverterID: String?
    private var inverterDetail: SolisAPI.InverterDetail?
    private var knownAlarmCodes: Set<String> = []
    private var didSeeFirstAlarmPoll = false
    /// Starts high so the first poll after launch always checks.
    private var pollsSinceAlarmCheck = Int.max
    private var alarms: [SolisAPI.Alarm] = []

    /// Low-battery levels already notified for, so each fires once per
    /// crossing rather than on every poll. Cleared per level as the battery
    /// recovers past it — see BatteryAlert.
    private var firedBatteryAlerts: Set<Int> = []

    private init() {}

    // MARK: - Lifecycle (enable / disable)

    func start() {
        // Something has to be in the menu bar before the first response
        // arrives, or the item is an empty click target.
        panelImage = renderPanelImage([PanelSegment(symbol: "sun.max.fill", text: "…")])

        // GSettings 'changed' handler from enable(): clear the session-expired
        // state so fresh tokens take effect immediately, then refetch.
        settingsObserver = settings.changed
            .sink { [weak self] in self?.settingsDidChange() }

        Task { await fetchSolarData() }
        startTimer()
    }

    func stop() {
        stopTimer()
        settingsObserver = nil
        refetchWorkItem?.cancel()
        refetchWorkItem = nil
    }

    private func settingsDidChange() {
        sessionExpired = false
        panelText = "Refreshing…"
        panelImage = renderPanelImage([PanelSegment(symbol: "arrow.clockwise", text: "Refreshing…")])

        // GSettings fired one signal per keystroke in the prefs entry rows.
        // Coalescing avoids hammering the API while a cookie is being pasted;
        // the resulting state is the same.
        refetchWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restartTimer()
            Task { await self.fetchSolarData() }
        }
        refetchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    // MARK: - Fetch

    private func fetchSolarData() async {
        let stationID = settings.stationID
        let cookie = settings.cookie
        let deviceID = settings.deviceID
        let secret = settings.signingSecret

        // Distinguished on purpose. No secret is a setup problem that signing in
        // will never fix, and reporting it as an expired session would send
        // someone round the login flow forever.
        guard !secret.isEmpty, !stationID.isEmpty else {
            showNotConfigured()
            return
        }
        guard !cookie.isEmpty else {
            showSessionExpired()
            return
        }

        let result = await SolisAPI.fetch(stationID: stationID, cookie: cookie,
                                          deviceID: deviceID, secret: secret)

        switch result {
        case .success(let data):
            // Alarms come from a second endpoint, awaited before updateUI so a
            // single poll produces one consistent picture.
            //
            // Throttled while nothing is wrong, and every poll once something
            // is — so a clearing outage is noticed promptly, while a quiet
            // system isn't paying for a request it will never learn from.
            //
            // Not gated on anything in the main response, deliberately.
            // `state`, `alarmCount`, `alarmLevel` and the three error flags
            // were all measured during a live NO-Grid alarm and every one read
            // exactly as it does when healthy. `state == 1` in particular would
            // mean only checking when the inverter isn't generating, i.e. never
            // catching a daytime alarm at all.
            // The inverter id comes from the station response, so no new
            // setting is needed to reach the device endpoints.
            if let id = data.str("inverterId"), !id.isEmpty { inverterID = id }

            if !alarms.isEmpty || pollsSinceAlarmCheck >= AlarmPolling.quietPollGap {
                pollsSinceAlarmCheck = 0
                if let id = inverterID,
                   let detail = await SolisAPI.fetchInverterDetail(
                    inverterID: id, cookie: cookie, deviceID: deviceID, secret: secret) {
                    inverterDetail = detail
                }
                // nil means the call failed — the previous list is kept rather
                // than treating a network blip as "all clear", which would fire
                // a spurious "restored" notification.
                if let fresh = await SolisAPI.fetchAlarms(
                    stationID: stationID, cookie: cookie, deviceID: deviceID, secret: secret) {
                    alarms = fresh
                }
            } else {
                pollsSinceAlarmCheck += 1
            }
            updateUI(data)
        case .sessionExpired:
            showSessionExpired()
        case .apiError(let message):
            showError(message)
        case .offline:
            showError("Offline")
        }
    }

    // MARK: - _updateUI

    private func updateUI(_ data: JSONDict) {
        let stationName = data.str("stationName") ?? "Solis Station"
        let pvPower     = data.num("power") ?? 0
        let pvPowerStr  = data.str("powerStr") ?? "kW"
        let dayEnergy   = data.num("dayEnergy") ?? 0
        let dayEnergyStr = data.str("dayEnergyStr") ?? "kWh"

        let batterySOC      = data.num("batteryPercent") ?? 0
        let batteryPowerKW  = data.num("batteryPowerV2") ?? 0
        let batteryPowerStr = data.str("batteryPowerStrV2") ?? "kW"

        // Load Power (familyLoadPower or totalLoadPowerOrigin / 1000)
        var loadKW = data.num("familyLoadPower") ?? 0
        if loadKW == 0, let origin = data.num("totalLoadPowerOrigin"), origin != 0 {
            loadKW = origin / 1000.0
        }

        // Grid Power
        let gridKW = data.num("psumV2") ?? 0

        // Station coordinates, for sunrise/sunset. Present in a live response;
        // optional so a station without them shows no sun times rather than
        // computing from a default of 0,0.
        //
        // Deliberately not quoted in a comment: a lat/long pair to four decimal
        // places locates a house to about a hundred metres, which is not
        // something a public repository needs to carry.
        let latitude  = data.num("latitude")
        let longitude = data.num("longitude")

        // Full reading timestamp as reported by the inverter, date + time +
        // offset, e.g. "02/08/2026 20:45:01 (UTC+05:00)".
        var timestamp = fullLocalTimestamp()
        if let raw = data.str("dataTimestampStr") {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { timestamp = trimmed }
        }

        // How old the reading itself is.
        //
        // Measured server-side where possible: dataTimestamp is when the
        // inverter reported, nowZoneTime is SolisCloud's own clock, both epoch
        // millis. Comparing those two avoids blaming a skewed Mac clock for a
        // stale inverter, and vice versa. A live sample had them 3.2 minutes
        // apart, which is the normal reporting lag.
        var dataAgeSeconds: Double?
        if let reported = data.num("dataTimestamp") {
            let reference = data.num("nowZoneTime") ?? (Date().timeIntervalSince1970 * 1000)
            let age = (reference - reported) / 1000
            // Negative means the inverter's clock is ahead of the server's;
            // absurdly large means a field that isn't what we think it is.
            // Neither is evidence of staleness, so both are ignored.
            if age >= 0, age < 30 * 24 * 3600 { dataAgeSeconds = age }
        }

        // Decided before anything reads it. The battery runtime (step 4) needs
        // to know whether we're off grid, but the grid section is step 6 — so
        // reading display.gridOutage there would use the *previous* poll's
        // answer and pick the wrong floor for the first four minutes of an
        // outage, while the log printed the new one.
        let gridOutageNow = alarms.contains { isGridLoss($0) }

        var next = DisplayState()

        // Sun times are computed here, before anything consumes them. Two
        // things now depend on "is the sun down" — the peak window's evening
        // state and the day-quality comparison — and both used to read a flag
        // the sun block hadn't set yet, so they lagged the sunrise/sunset
        // boundary by a full poll.
        let sun = latitude.flatMap { lat in
            longitude.map { lon in sunTimes(latitude: lat, longitude: lon) }
        } ?? nil
        let now = Date()
        if let sun {
            isDaytime = now >= sun.rise && now < sun.set
            afterSunset = now >= sun.set
        }

        if let row = peakWindowRow(afterSunset: afterSunset) {
            next.peakWindowLabel = row.label
            next.peakWindowText  = row.value
            next.peakWindowLive  = row.live
        }

        // 1. Panel indicator.
        //
        // The slot state machine runs on every sample regardless of the
        // active mode, so switching *to* adaptive shows the right metrics
        // immediately instead of spending confirmPolls settling.
        updateAdaptiveSlots(pvPower: pvPower, batterySOC: batterySOC, batteryPowerKW: batteryPowerKW)

        // Low battery swaps 🔋 for 🪫 everywhere the battery is shown. Computed
        // here, once, rather than at each of the four use sites — the panel and
        // the popup showing different icons for one reading is exactly the kind
        // of contradiction this project has already been bitten by twice.
        let battIcon = batteryIcon(for: batterySOC)
        next.batteryIcon = battIcon
        next.batterySymbol = batterySymbol(for: batterySOC, powerKW: batteryPowerKW)
        next.batteryLow = batterySOC < BatteryAlert.lowIconSOC
        next.batteryCharging = batteryPowerKW > Adaptive.powerFloor

        // Segments are the rendered form; panelText is the same content as a
        // string, kept for the log line and panel-debug-tick. Both are built
        // from the same pieces so they can't drift.
        // The sun brightens for the peak window's three hours and is the
        // lesser glyph the rest of the time, so the menu bar carries the "these
        // are the good hours" signal it otherwise has no room to state.
        //
        // Menu bar only, on purpose. The window says it in words ("Peak window
        // — Now, until 15:00"), so changing its glyph too would be a second
        // encoding of one fact. Not a disagreement between the surfaces: one
        // has room for a sentence and the other doesn't.
        //
        // Noted for whoever revisits this: min vs max is a difference of a few
        // ray lengths at 12pt, and an ambient signal has to be legible from
        // memory rather than by comparison. Outline-to-filled would read louder
        // if this turns out too quiet in practice.
        let solarSymbol = next.peakWindowLive ? "sun.max.fill" : "sun.min.fill"
        let solarSeg   = PanelSegment(symbol: solarSymbol, text: "\(toFixed(pvPower, 2)) \(pvPowerStr)")
        let loadSeg    = PanelSegment(symbol: "house", text: "\(toFixed(loadKW, 2)) kW")
        let batterySeg = PanelSegment(symbol: next.batterySymbol,
                                      accessorySymbol: next.batteryCharging ? "bolt.fill" : nil,
                                      text: "\(jsNum(batterySOC))%")

        var segments: [PanelSegment]
        switch settings.panelDisplayMode {
        case "full":
            segments = [solarSeg, loadSeg, batterySeg]
        case "minimal":
            segments = [solarSeg]
        // Adaptive is a deliberate addition, not part of the GNOME original —
        // its three modes are ported unchanged above and below this case.
        case "adaptive":
            // powerText here too, so the menu bar and the window print one
            // reading one way. The ported modes keep GNOME's format.
            let first = adaptiveShowingLoad
                ? PanelSegment(symbol: "house", text: powerText(loadKW))
                : PanelSegment(symbol: solarSymbol, text: powerText(pvPower))
            let second = adaptiveShowingGrid
                ? PanelSegment(symbol: "powerplug.fill", text: gridPanelText(gridKW))
                : batterySeg
            segments = [first, second]
        default:
            segments = [solarSeg, batterySeg]
        }

        // A stale feed is flagged in the menu bar too. Without it the panel
        // shows hours-old numbers with complete confidence, which is the whole
        // problem this is meant to solve.
        if next.dataStale {
            segments.insert(PanelSegment(symbol: "exclamationmark.triangle.fill", text: ""), at: 0)
        }

        // The string form keeps the emoji: it exists for the log, and an
        // SF Symbol has no text representation to print there.
        let emojiFor: (PanelSegment) -> String = { seg in
            switch seg.symbol {
            case "sun.max.fill", "sun.min.fill": return "☀️"
            case "exclamationmark.triangle.fill": return "⚠️"
            case "house":           return "⚡"
            case "bolt.fill":       return "⚡"
            case "powerplug.fill":  return "🔌"
            case .some(let s) where s.hasPrefix("battery"): return battIcon
            default:                return ""
            }
        }
        panelText = segments
            .map { "\(emojiFor($0)) \($0.text)".trimmingCharacters(in: .whitespaces) }
            .joined(separator: " | ")

        // Diagnostic tick, off unless panel-debug-tick is set. Appended after
        // the mode switch so it applies to every mode. See SolisSettings.
        pollCount += 1
        if settings.panelDebugTick {
            panelText += " #\(pollCount)"
            segments.append(PanelSegment(symbol: nil, text: "#\(pollCount)"))
        }

        panelImage = renderPanelImage(segments)

        // One line per poll, so the panel string the model produced can be
        // compared against what the menu bar is actually rendering. This is
        // the only way to tell "the value didn't change" apart from "the label
        // didn't re-render" from outside the process: no screen recording, and
        // no accessibility permission to read the status item's title.
        // Follow with:  log stream --predicate 'process == "SolisSolarMonitor"'
        //
        // Must be NSLog("%@", s), never NSLog(s): panelText contains a literal
        // "%" from the battery percentage, and NSLog treats its first argument
        // as a format string. Interpolating directly printed "🔋 87" with the
        // % silently eaten along with the token after it — and with no varargs
        // supplied, a "%" followed by a conversion character reads garbage.
        let diagnostic = "SolisSolarMonitor: panel=\"\(panelText)\" mode=\(settings.panelDisplayMode) "
            + "pv=\(toFixed(pvPower, 3)) load=\(toFixed(loadKW, 3)) soc=\(jsNum(batterySOC)) "
            + "batt=\(toFixed(batteryPowerKW, 3)) grid=\(toFixed(gridKW, 3)) | "
            + "slots=\(adaptiveShowingLoad ? "LOAD" : "SOLAR")/\(adaptiveShowingGrid ? "GRID" : "BATT") "
            + "pending=\(solarSlotPendingPolls)/\(gridSlotPendingPolls) confirmPolls=\(confirmPolls) "
            + "dataAge=\(dataAgeSeconds.map { String(format: "%.0fs", $0) } ?? "unknown") | "
            // Logged, not acted on. These are the grid-presence candidates, and
            // every sample so far was taken during one outage: uAc1 and fac read
            // 0, currentState read 1015. What they read with the grid PRESENT is
            // unknown, so this line exists to capture that the moment it happens
            // rather than shipping a guess. `data.state` was convincing from a
            // single sample too.
            + "uAc1=\(inverterDetail?.gridVoltage.map { toFixed($0, 1) } ?? "?") "
            + "fac=\(inverterDetail?.gridFrequency.map { toFixed($0, 2) } ?? "?") "
            + "currentState=\(inverterDetail?.currentState ?? "?") "
            + "soh=\(inverterDetail?.batteryHealthSOH.map { toFixed($0, 0) } ?? "?") "
            + "floors(onGrid/eps/offGrid)="
            + "\(inverterDetail?.dischargeFloorSOC.map { toFixed($0, 0) } ?? "?")/"
            + "\(inverterDetail?.epsFloorSOC.map { toFixed($0, 0) } ?? "?")/"
            + "\(inverterDetail?.offGridFloorSOC.map { toFixed($0, 0) } ?? "?") "
            + "floorUsed=\(toFixed(dischargeFloor(gridOutage: gridOutageNow), 0)) "
            + "outage=\(gridOutageNow) "
            + "invTemp=\(inverterDetail?.internalTemperature.map { toFixed($0, 1) } ?? "?")"
        NSLog("%@", diagnostic)

        // 2. Header. "Connected", not "Online" — this only ever means the
        // API call itself succeeded (a failed fetch never reaches this line;
        // see showError/showSessionExpired), which is a different thing from
        // the Grid card's "Online"/"Offline" a few lines down. They used to
        // share the word "Online" for two unrelated concepts. Not merged
        // into one health signal: data.state's non-1 values were checked
        // live and don't reliably mean "fault" — a reading of state=3 showed
        // solar actively generating and powering the home with zero alarms
        // reported, i.e. state disagrees with every other health signal in
        // the same response. Gating the badge on it would very likely have
        // produced false "Grid Fault" alarms.
        next.stationTitle = "Station: \(stationName)"
        next.timestamp    = "Updated: \(timestamp)"
        next.badgeText    = "Connected"
        next.badgeOnline  = true

        // 3. Solar card. powerText, not the GNOME "0.00 kW" — the window is a
        // redesign now, and these strings feed the summary tiles where mixed
        // formats were the specific thing that looked broken.
        next.pvPower = powerText(pvPower)
        next.solarAsleep = pvPower <= Adaptive.powerFloor
        next.solarTodayZero = dayEnergy <= 0
        next.loadIdle = loadKW <= Adaptive.powerFloor
        next.batteryIdle = abs(batteryPowerKW) <= Adaptive.powerFloor
        next.gridIdle = abs(gridKW) <= GridFlow.directionFloorKW
        next.solarTodayText = energyText(dayEnergy, dayEnergyStr)

        // From the station response rather than the inverter one: both carry
        // homeLoadTodayEnergy, but this is fetched every poll where the
        // inverter detail is throttled, so it's the fresher of the two.
        if let usedToday = data.num("homeLoadTodayEnergy") {
            next.usedTodayZero = usedToday <= 0
            next.usedTodayText = energyText(usedToday, data.str("homeLoadTodayEnergyStr") ?? "kWh")
        }

        next.solarComparisonText = solarComparison(data, todayKWh: dayEnergy,
                                                   todayUnit: dayEnergyStr,
                                                   solarAsleep: next.solarAsleep)

        // 4. Battery
        next.batterySOC = "\(jsNum(batterySOC))%"
        if batteryPowerKW < -0.01 {
            next.batteryFlowText = "Discharging \(toFixed(abs(batteryPowerKW), 2)) \(batteryPowerStr)"
        } else if batteryPowerKW > 0.01 {
            next.batteryFlowText = "Charging \(toFixed(batteryPowerKW, 2)) \(batteryPowerStr)"
        } else {
            next.batteryFlowText = "Idle"
        }
        let runtime = batteryRuntimeHours(socPercent: batterySOC, powerKW: batteryPowerKW,
                                          gridOutage: gridOutageNow)
        next.batteryTimeText = runtime.map { "about \(durationText($0.hours)) \($0.suffix)" }
        next.batteryEndTimeText = runtime.map { clockTime(inHours: $0.hours) }
        next.batteryEndLabel = runtime?.endLabel ?? "On battery until"
        next.batteryCapacityUnset = settings.batteryCapacityKWh <= 0

        // 5. Load. gridPurchasedDayEnergy — confirmed present in a live
        // response (2.37 kWh alongside gridPurchasedDayEnergyStr "kWh"), not
        // assumed from the field's name. The "Day" variant is used rather than
        // the bare gridPurchasedEnergy, which held the same value: the intent
        // here is explicitly today, and identical values today don't promise
        // the two fields mean the same thing tomorrow.
        next.loadPower = powerText(loadKW)
        if let importedToday = data.num("gridPurchasedDayEnergy") {
            next.gridBoughtZero = importedToday <= 0
            next.gridBoughtTodayText = energyText(importedToday, data.str("gridPurchasedDayEnergyStr") ?? "kWh")
        } else {
            // Older firmware or a partial response — say so rather than
            // printing a confident 0.00 kWh that looks like a real reading.
            next.gridBoughtTodayText = "—"
        }
        if let costToday = data.num("gridPurchasedDayIncome") {
            // "Income" in the field name; for purchases it is what was paid.
            // Live sample: 45.98 against 2.42 kWh, i.e. ~19 PKR/kWh, which
            // matches a real tariff — so it is a cost, not a credit.
            let currency = data.str("gridPurchasedDayIncomeUnit") ?? ""
            next.gridCostTodayText = energyText(costToday, currency)
                .trimmingCharacters(in: .whitespaces)
        } else {
            next.gridCostTodayText = "—"
        }

        // 6. Grid. `data.state` is deliberately not read at all any more —
        // measured against a real outage it carried no grid information, and
        // the app inferred a "fault" from it for months. Grid health now comes
        // only from the alarm endpoint.
        next.gridPower = gridText(gridKW)

        // Inverter temperature. Internal, not ambient: Solis documents 110°C
        // internal as the shutdown point (= 60°C ambient) and states that
        // readings above 85°C are normal and "not cause for alarm", so the
        // limit is only named when it's actually being approached.
        if let temperature = inverterDetail?.internalTemperature, temperature > 0 {
            next.inverterTempHot = temperature >= Thermal.warnCelsius
            next.inverterTempText = next.inverterTempHot
                ? "\(toFixed(temperature, 0)) °C · limit \(Int(Thermal.shutdownCelsius)) °C"
                : "\(toFixed(temperature, 0)) °C"
        }

        // Alarms, from the previous /alarm/list result.
        next.gridOutage = gridOutageNow
        if let alarm = alarms.first {
            next.alarmSummary = next.gridOutage ? "Grid outage" : alarm.message
            next.alarmDetail = alarm.beganText.isEmpty
                ? alarm.message
                : "\(alarm.message) · since \(shortClock(alarm.beganText))"
            if alarms.count > 1 {
                next.alarmSummary = "\(next.alarmSummary ?? "Alarm") + \(alarms.count - 1) more"
            }
        }

        // 6b. Hero summary (design direction A).
        //
        // The hero is whichever of solar/load currently carries information,
        // and it is deliberately the SAME choice the menu bar's first slot
        // makes — adaptiveShowingLoad — rather than a second, parallel rule.
        // Two independent "is solar alive" tests would eventually disagree,
        // and the window contradicting the menu bar is the exact failure this
        // project has already hit with the flow diagram and the status pill.
        next.heroIsSolar = !adaptiveShowingLoad
        let heroParts = powerParts(next.heroIsSolar ? pvPower : loadKW)
        next.heroLabel = next.heroIsSolar ? "Solar Output" : "Home Load"
        next.heroValue = heroParts.value
        next.heroUnit  = heroParts.unit
        next.heroCaption = heroCaption(
            pvPower: pvPower, loadKW: loadKW, batterySOC: batterySOC,
            batteryPowerKW: batteryPowerKW, gridKW: gridKW
        )
        // Sun times, and the caption's second clause.
        //
        // In daylight the battery's runtime is the wrong question — it is
        // being charged or topped up, and the number that decides anything is
        // how much generating time is left. After dark that inverts: the sun
        // is not coming back tonight and the battery is all there is. So the
        // caption carries whichever clock actually constrains the next few
        // hours, rather than always the battery.
        var daylightClause: String?
        if let sun {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "HH:mm"

            if now < sun.rise {
                next.sunLabel = "Sunrise"
                next.sunTimeText = f.string(from: sun.rise)
            } else if now < sun.set {
                next.sunLabel = "Sunset"
                next.sunTimeText = f.string(from: sun.set)
                let hours = sun.set.timeIntervalSince(now) / 3600
                if hours > 0 { daylightClause = "about \(durationText(hours)) of daylight left" }
            } else {
                // After sunset the useful sun fact is tomorrow's sunrise, and
                // sunTimes is date-based, so ask it about tomorrow.
                next.sunLabel = "Sunrise"
                let tomorrow = now.addingTimeInterval(24 * 3600)
                if let next2 = latitude.flatMap({ lat in
                    longitude.map { lon in sunTimes(latitude: lat, longitude: lon, date: tomorrow) }
                }) ?? nil {
                    next.sunTimeText = f.string(from: next2.rise)
                }
            }
        }

        // Set after the sun block, which is what decides isDaytime for this
        // poll. Assigned earlier it would carry the previous poll's answer and
        // lag the sunrise/sunset boundary by one interval.
        next.sunTodayComparison = isDaytime ? sunTodayComparison : nil

        // The estimate belongs in the glance state, not behind Details — it is
        // the only line in the window that answers a question ("will it last?")
        // rather than reporting a measurement.
        if let clause = daylightClause {
            next.heroCaption += " · \(clause)"
        } else if let remaining = next.batteryTimeText {
            next.heroCaption += " · \(remaining)"
        }

        // Station name and a connection dot. The reading's time used to sit
        // here too, but the details section already prints it in full and to
        // the second, so this was two clocks for one fact.
        next.statusLine = stationName
        next.statusOK   = true
        if let age = dataAgeSeconds, age >= StaleData.thresholdSeconds {
            next.dataStale = true
            next.dataAgeText = "No update for \(ageText(age))"
        }

        // 7. Desktop notifications on alarm transitions.
        //
        // Was driven by `state == 1`, which fired at dusk every evening and
        // stayed silent through an actual outage. Now driven by the alarm list,
        // which named the outage explicitly.
        notifyAlarmChanges(stationName: stationName)

        // 7b. Low-battery notifications while the battery is under load.
        checkBatteryAlerts(
            batterySOC: batterySOC,
            batteryPowerKW: batteryPowerKW,
            stationName: stationName
        )

        // Kicked off, not awaited: a slow or unreachable forecast must never
        // hold up the reading the window is about to show.
        if let latitude, let longitude {
            Task { await refreshPeakWindowIfNeeded(latitude: latitude, longitude: longitude) }
        }

        sessionExpired = false
        display = next
    }

    private enum Curtailment {
        /// At or above this, with no charge flowing, the battery is treated as
        /// unable to absorb more. Not 100: a bank can sit at 99% for a long
        /// while with the BMS refusing further charge, and the cap is just as
        /// real there.
        static let fullSOC = 98.0
    }

    private enum Thermal {
        /// Documented by Solis: 110°C internal is where the inverter shuts
        /// down (it corresponds to 60°C ambient). Their support note also says
        /// internal readings above 85°C are normal, which is why nothing is
        /// flagged until well past that.
        static let shutdownCelsius = 110.0
        static let warnCelsius = 100.0
    }

    private enum AlarmPolling {
        /// Polls to skip between alarm checks while the system is clear. At the
        /// 240 s interval that's a worst-case 8 minutes to notice a new alarm,
        /// against ~180 extra requests a day instead of 360.
        ///
        /// Expressed in polls rather than seconds, which normally would be a
        /// bug in this codebase — but here the quantity genuinely is "how many
        /// station reads to piggyback on", and the cost scales with the poll
        /// rate exactly as intended.
        static let quietPollGap = 2
    }

    // MARK: - Alarms

    /// Code 1015 / "NO-Grid" is the inverter's grid-loss alarm, confirmed
    /// against a live outage. Matched on the message too, since the code list
    /// is undocumented and may vary by firmware.
    private func isGridLoss(_ alarm: SolisAPI.Alarm) -> Bool {
        alarm.code == "1015"
            || alarm.message.replacingOccurrences(of: "-", with: "").lowercased() == "nogrid"
    }

    /// "18/08/2026 18:33 (UTC+05:00)" -> "18:33". Falls back to the whole
    /// string if the shape isn't what's expected.
    private func shortClock(_ timestamp: String) -> String {
        for field in timestamp.split(separator: " ") {
            let parts = field.split(separator: ":")
            guard parts.count == 2,
                  let h = Int(parts[0]), (0...23).contains(h),
                  let m = Int(parts[1]), (0...59).contains(m) else { continue }
            return String(format: "%02d:%02d", h, m)
        }
        return timestamp
    }

    /// Fires once when an alarm appears and once when it clears.
    ///
    /// Keyed on alarm code, so an alarm that persists for hours notifies once.
    /// The first poll after launch is deliberately silent about pre-existing
    /// alarms — waking the Mac shouldn't replay an outage that started before
    /// the app was running; the warning row shows it instead.
    private func notifyAlarmChanges(stationName: String) {
        let current = Set(alarms.map(\.code))
        defer { knownAlarmCodes = current }
        guard didSeeFirstAlarmPoll else {
            didSeeFirstAlarmPoll = true
            return
        }

        for alarm in alarms where !knownAlarmCodes.contains(alarm.code) {
            let isGrid = isGridLoss(alarm)
            Notifier.shared.notify(
                title: isGrid ? "⚠️ Solis Grid Outage" : "⚠️ Solis Alarm: \(alarm.message)",
                body: isGrid
                    ? "\(stationName) lost grid power at \(shortClock(alarm.beganText)). Running on battery and solar."
                    : "\(stationName) reported \(alarm.message) (code \(alarm.code)) at \(shortClock(alarm.beganText))."
            )
        }

        for cleared in knownAlarmCodes.subtracting(current) {
            let wasGrid = cleared == "1015"
            Notifier.shared.notify(
                title: wasGrid ? "✅ Solis Grid Restored" : "✅ Solis Alarm Cleared",
                body: wasGrid
                    ? "Grid power is back for \(stationName)."
                    : "\(stationName) cleared alarm code \(cleared)."
            )
        }
    }

    // MARK: - Stale data

    private enum StaleData {
        /// How old a reading has to be before the window says so.
        ///
        /// The inverter normally reports every few minutes — a live sample was
        /// 3.2 minutes behind the server's own clock — so 15 minutes is well
        /// clear of a slow-but-healthy feed while still catching an outage
        /// within one or two polls of it starting.
        static let thresholdSeconds: Double = 15 * 60
    }

    /// "25 min", "2 h 10 min", "3 days". Coarse on purpose: past a certain
    /// point the only thing that matters is the order of magnitude.
    private func ageText(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 {
            let rest = minutes % 60
            return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
        }
        let days = hours / 24
        return days == 1 ? "1 day" : "\(days) days"
    }

    // MARK: - Forecast peak window

    /// "3% above last week", or "about the same as last week" inside the noise.
    ///
    /// ±5% is treated as no difference: day-to-day irradiance swings far more
    /// than that, so calling a 2% difference "above average" would dress noise
    /// up as a finding.
    private static func comparisonText(percent: Double?, days: Int) -> String? {
        guard let percent, days >= 2 else { return nil }
        let period = days >= 6 ? "last week" : "recent days"
        if abs(percent) < 5 { return "about the same as \(period)" }
        let direction = percent > 0 ? "above" : "below"
        return "\(Int(abs(percent).rounded()))% \(direction) \(period)"
    }

    /// The row's three states, derived from the clock on every poll.
    ///
    /// Derived here rather than stored when the forecast arrives, because the
    /// state changes with time, not with data: the forecast is fetched every
    /// three hours, so a value fixed at fetch time would still say "12:00 –
    /// 15:00" at half past two.
    private func peakWindowRow(afterSunset: Bool) -> (label: String, value: String, live: Bool)? {
        guard let window = peakWindow else { return nil }
        let now = Date()

        // Over. Today's window is history, so point at tomorrow's — which is
        // when "plan the laundry for 11:00" is actually actionable. Falls back
        // to nothing if tomorrow's forecast is missing.
        if now >= window.end {
            // Tomorrow's plan waits until the sun is actually down. Today's
            // window can end hours before sunset — 12:30–15:30 against a 19:03
            // sunset — and there is still usable daylight in between, so
            // pointing at tomorrow then would be premature.
            guard afterSunset, let next = tomorrowPeakWindow else { return nil }
            return ("Peak window tomorrow", "\(next.startText) – \(next.endText)", false)
        }

        // Underway. The only number that still matters is when it ends.
        if now >= window.start {
            return ("Peak window", "Now, until \(window.endText)", true)
        }

        // Still ahead.
        return ("Peak window today", "\(window.startText) – \(window.endText)", false)
    }

    /// Refetches at most every 3 hours, and always after the date rolls over.
    ///
    /// The forecast is not poll-rate data: irradiance predictions update a few
    /// times a day, so asking on every 4-minute cycle would be ~360 requests a
    /// day to a free service for an answer that moves twice. The date check
    /// exists because a Mac left asleep overnight would otherwise wake showing
    /// yesterday's window.
    private func refreshPeakWindowIfNeeded(latitude: Double, longitude: Double) async {
        let now = Date()
        if let fetched = peakWindowFetchedAt,
           now.timeIntervalSince(fetched) < 3 * 3600,
           Calendar.current.isDate(fetched, inSameDayAs: now) {
            return
        }
        // Stamped before the call, so a failing request doesn't retry on every
        // poll for the rest of the day.
        peakWindowFetchedAt = now

        guard let forecast = await SolarForecast.fetch(latitude: latitude, longitude: longitude) else {
            return
        }
        peakWindow = forecast.window
        tomorrowPeakWindow = forecast.tomorrowWindow
        sunTodayComparison = Self.comparisonText(percent: forecast.dayVersusRecentPercent,
                                                 days: forecast.recentDayCount)
        display.sunTodayComparison = isDaytime ? sunTodayComparison : nil
        if let window = forecast.window {
        if let row = peakWindowRow(afterSunset: afterSunset) {
            display.peakWindowLabel = row.label
            display.peakWindowText  = row.value
            display.peakWindowLive  = row.live
        }
            NSLog("%@", "SolisSolarMonitor: peak window \(window.startText)–\(window.endText), "
                + "\(Int((window.share * 100).rounded()))% of today's sun")
        }
        NSLog("%@", "SolisSolarMonitor: today's sun \(sunTodayComparison ?? "unknown")")
    }

    // MARK: - Menu bar label rendering

    /// Lays the panel out as a normal SwiftUI view and renders it to a
    /// template NSImage for MenuBarExtra's label.
    ///
    /// Why this exists rather than just handing the label a view: MenuBarExtra
    /// does not render Image views in its label — not inside an HStack, and not
    /// interpolated into a Text (both were tried; the images vanished and only
    /// the text drew). An *Image* label is supported, so the entire label is
    /// drawn offscreen and passed as one.
    ///
    /// The result is marked `isTemplate`, which is what makes it invert
    /// correctly against a light or dark menu bar and when the item is
    /// highlighted. Template rendering uses only the alpha channel, so this
    /// label is monochrome by construction — the battery's low-charge red
    /// can't survive here, and belongs in the window instead.
    private func renderPanelImage(_ segments: [PanelSegment]) -> NSImage? {
        // Matches the menu bar's own metrics rather than a guess: NSFont's
        // menu bar size, and a height that leaves the standard breathing room.
        let pointSize = NSFont.systemFontSize(for: .regular)

        let content = HStack(spacing: 5) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Text(verbatim: "|").opacity(0.35)
                }
                // The icon and its accessory are their own tight group, so the
                // bolt reads as part of the battery rather than as a third
                // item spaced like one.
                if let symbol = segment.symbol {
                    HStack(spacing: 1) {
                        Image(systemName: symbol)
                            .font(.system(size: pointSize - 1))
                        if let accessory = segment.accessorySymbol {
                            Image(systemName: accessory)
                                .font(.system(size: pointSize - 4))
                        }
                    }
                }
                Text(verbatim: segment.text)
                    .font(.system(size: pointSize))
                    .monospacedDigit()
            }
        }
        // Black, opaque: a template image keeps only alpha, so the colour is
        // irrelevant but full opacity is not.
        .foregroundStyle(.black)
        .padding(.horizontal, 2)
        // Constrain the height rather than scaling the finished bitmap.
        //
        // The first version rendered at natural size (21pt, varying with which
        // glyphs were present) and then shrank the image to 17pt, which also
        // shrank the type: 13pt text drawn and displayed at 13 x 17/21 ≈ 10.5,
        // noticeably smaller than every neighbouring menu bar item. Fixing the
        // frame keeps the text at the system's own menu bar size and makes the
        // height uniform across states, which is what the normalisation was
        // actually for. 18pt is the conventional status item height.
        .frame(height: 18)

        let renderer = ImageRenderer(content: content)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer.scale = scale

        guard let cgImage = renderer.cgImage else { return nil }

        // Point size is the rendered size divided by the scale — no further
        // adjustment. The frame above already fixed the height, and rescaling
        // here is exactly what made the type too small.
        let image = NSImage(cgImage: cgImage,
                            size: NSSize(width: CGFloat(cgImage.width) / scale,
                                         height: CGFloat(cgImage.height) / scale))
        image.isTemplate = true
        return image
    }

    // MARK: - Grid direction

    private enum GridFlow {
        /// Below this the grid is called Balanced rather than Importing or
        /// Exporting.
        ///
        /// Was 0.005 kW — 5 watts, inherited from the GNOME original. On a 6 kW
        /// system that is a rounding error, and it produced the screenshot
        /// where the window announced "Importing from Grid" over a 0.05 kW
        /// trickle while the hero caption said "Running on battery". Both were
        /// technically true and together they read as a contradiction. 50 W is
        /// still small enough to catch any import worth naming.
        ///
        /// The displayed magnitude is unaffected — this only gates the word.
        static let directionFloorKW = 0.05
    }

    /// Grid magnitude, no direction marker. Shared by the menu bar slot and
    /// the window's Grid tile so one reading reads one way in both.
    ///
    /// The ↓/↑ arrows were removed on request. They were also close to
    /// meaningless on this system: without net metering the grid only ever
    /// imports, so the arrow was the same glyph on every non-zero reading —
    /// decoration that looked like information. Direction, where it genuinely
    /// changes, is still stated in words by the hero caption ("Drawing from
    /// the grid" / "Exporting to the grid").
    private func gridText(_ gridKW: Double) -> String {
        powerText(abs(gridKW))
    }

    // MARK: - Today vs the month's average

    /// "7% above 11.2 kWh" — today's generation against the average of the
    /// month's *other* days.
    ///
    /// Today is excluded from the baseline on purpose: comparing a value
    /// against an average it is itself part of pulls the average toward it and
    /// flattens the very difference being reported. On the 1st there are no
    /// other days, so there is no comparison to make.
    ///
    /// The unit check is not defensive padding — this API genuinely mixes
    /// units across periods. A live response returned `monthEnergyStr` as kWh
    /// while `yearEnergyStr` was MWh, so subtracting one field from another
    /// without comparing their unit strings would silently be out by 1000x.
    private func solarComparison(_ data: JSONDict, todayKWh: Double, todayUnit: String,
                                 solarAsleep: Bool) -> String? {
        // Only once the day's generation is finished. Comparing a running
        // total against a full-day average is comparing different things: at
        // 10am a perfectly normal day reads "70% below average", and at dawn
        // it reads "100% below", which is alarming and means nothing. Waiting
        // for solar to go quiet is the cheapest way to know today is complete
        // without intraday history to compare hour-for-hour.
        guard solarAsleep, todayKWh > 0.05 else { return nil }

        guard let monthTotal = data.num("monthEnergy") else { return nil }
        let monthUnit = data.str("monthEnergyStr") ?? "kWh"
        guard monthUnit == todayUnit else { return nil }

        let dayOfMonth = Calendar.current.component(.day, from: Date())
        guard dayOfMonth > 1 else { return nil }

        let priorDays = Double(dayOfMonth - 1)
        let priorTotal = monthTotal - todayKWh
        guard priorTotal > 0 else { return nil }

        let average = priorTotal / priorDays
        guard average > 0.05 else { return nil }

        let deltaPercent = (todayKWh - average) / average * 100
        let averageText = "\(energyText(average, monthUnit))"

        // Under 5% either way is noise on a number this variable; calling that
        // "above average" would read as a finding when it isn't one.
        if abs(deltaPercent) < 5 { return "about average · \(averageText)" }
        let direction = deltaPercent > 0 ? "above" : "below"
        return "\(Int(abs(deltaPercent).rounded()))% \(direction) \(averageText)"
    }

    /// The SOC the battery will actually stop supplying the house at.
    ///
    /// The inverter reports three floor-shaped settings that disagree —
    /// socDischargeSet 15, epsDDepth 20, offGridDDepth 30 on this system — and
    /// the response says nothing about which governs when. The user's own
    /// observation was "around 25%", which sits among them rather than matching
    /// any. So this doesn't pretend to know; it picks by which error is
    /// survivable:
    ///
    /// - **On grid**, reaching the floor is a non-event: the grid takes over,
    ///   nothing goes dark, and being a few points out costs nothing. So the
    ///   reported on-grid setting is used as-is.
    /// - **Off grid**, overstating runtime is the one error with consequences —
    ///   you plan around twelve hours and the house drops out after eight. So
    ///   the most conservative of the three is used, deliberately erring short.
    ///
    /// The ambiguity is resolvable by observation rather than argument: the SOC
    /// at which discharge actually stops is logged every poll, so an outage that
    /// runs to the floor answers this permanently. Until then, short is safe.
    private func dischargeFloor(gridOutage: Bool) -> Double {
        let reported = [inverterDetail?.dischargeFloorSOC,
                        inverterDetail?.epsFloorSOC,
                        inverterDetail?.offGridFloorSOC].compactMap { $0 }.filter { $0 > 0 }
        guard !reported.isEmpty else { return settings.batteryReserveSOC }

        if gridOutage {
            return reported.max() ?? settings.batteryReserveSOC
        }
        return inverterDetail?.dischargeFloorSOC ?? reported.min() ?? settings.batteryReserveSOC
    }

    // MARK: - Battery time remaining

    /// "about 5 h 20 m left" / "about 2 h to full", or nil.
    ///
    /// nil whenever the answer would be a guess: no capacity configured, the
    /// battery idle, or a run time so long the estimate is meaningless. The
    /// window says nothing rather than something unfounded.
    ///
    /// Deliberately a naive SOC x capacity / power calculation at the current
    /// instant. It does not model the load changing, temperature, inverter
    /// efficiency, or the fact that a real inverter stops discharging above
    /// 0% — so it reads "about", and it is a decision aid, not a guarantee.
    private func batteryRuntimeHours(socPercent: Double, powerKW: Double, gridOutage: Bool)
        -> (hours: Double, suffix: String, endLabel: String)? {
        // Nameplate capacity is still a setting — no endpoint reports it in kWh
        // or Ah (checked across all 809 inverter fields and the battery pile
        // detail; bmsCapacityTotal is 0). But the pack's health is reported, and
        // a 96% pack holds 96% of nameplate, so the estimate uses what the
        // battery can actually store today rather than what it stored when new.
        let health = (inverterDetail?.batteryHealthSOH).map { $0 / 100 } ?? 1.0
        let capacity = settings.batteryCapacityKWh * min(max(health, 0.5), 1.0)
        guard capacity > 0 else { return nil }

        let hours: Double
        let suffix: String
        let endLabel: String
        if powerKW < -Adaptive.powerFloor {
            // Energy above the *reserve*, not above empty. An inverter that
            // stops at 25% never delivers the bottom quarter of the bank, so
            // counting it would overstate the runtime by that share — at 54%
            // with a 25% floor the usable portion is 29 points, not 54.
            let floorSOC = dischargeFloor(gridOutage: gridOutage)
            let usableSOC = max(0, socPercent - floorSOC)
            hours = (usableSOC / 100 * capacity) / abs(powerKW)
            suffix = "left"
            // Not "empty by": with a reserve set, this is the moment the
            // inverter stops supporting the house, not the moment the battery
            // is flat — it keeps drifting down on standby draw well past it.
            // "On battery until" says what actually ends.
            endLabel = "On battery until"
        } else if powerKW > Adaptive.powerFloor {
            hours = ((100 - socPercent) / 100 * capacity) / powerKW
            suffix = "to full"
            endLabel = "Full at"
        } else {
            return nil
        }

        guard hours.isFinite, hours > 0, hours < 48 else { return nil }
        return (hours, suffix, endLabel)
    }

    /// The wall-clock time `hours` from now, as "01:10". Crossing midnight is
    /// left implicit — the estimate is capped at 48 hours, and a date stamp on
    /// a two-hour projection would be more noise than help.
    private func clockTime(inHours hours: Double) -> String {
        let end = Date().addingTimeInterval(hours * 3600)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: end)
    }

    /// 5.34 -> "5 h 20 m", 0.75 -> "45 m". Minutes are rounded to 5 so the
    /// estimate doesn't imply a precision the inputs don't have.
    private func durationText(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60 / 5).rounded() * 5)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h == 0 { return "\(max(m, 5)) m" }
        if m == 0 { return "\(h) h" }
        return "\(h) h \(m) m"
    }

    // MARK: - Hero summary helpers

    /// One sentence describing where the house's power is coming from, in the
    /// words someone would use out loud — this replaces four separate row
    /// subtitles, so it has to cover the ordinary cases without hedging.
    ///
    /// Thresholds match the ones the cards and the flow diagram already use
    /// (±0.01 kW for power, ±0.005 kW for grid direction) so the sentence can
    /// never contradict the numbers sitting directly above it.
    private func heroCaption(pvPower: Double, loadKW: Double, batterySOC: Double,
                             batteryPowerKW: Double, gridKW: Double) -> String {
        let solarAlive  = pvPower > 0.01
        let charging    = batteryPowerKW > 0.01
        let discharging = batteryPowerKW < -0.01
        // Full and no longer accepting charge. Both halves matter: at 98% and
        // still charging the array isn't capped yet, it's finishing the job.
        let batteryFull = batterySOC >= Curtailment.fullSOC
            && abs(batteryPowerKW) <= Adaptive.powerFloor
        // Same floor the Grid row's word uses, so the caption and that row can
        // never describe one reading two ways.
        let importing   = gridKW < -GridFlow.directionFloorKW
        let exporting   = gridKW > GridFlow.directionFloorKW

        // Curtailment, checked before anything else because it reframes
        // everything after it.
        //
        // With the battery full and no export path, the inverter has nowhere to
        // put surplus generation, so it throttles the array down to whatever
        // the house happens to be drawing. Conservation forces solar == load,
        // which is why the hero and the Home tile show the same number in this
        // state — that identical pair was the clue that led here.
        //
        // The wording claims only what is certain: that output is *capped*.
        // Saying how much is being lost would need modelled clear-sky output,
        // and the derate factors that go into it are guesses. The cap is a
        // fact; the loss would be an estimate dressed as one.
        if solarAlive, batteryFull, !exporting {
            return "Battery full — solar capped at house load"
        }

        switch (solarAlive, charging, discharging) {
        case (true, true, _):
            return "Solar powering the house and charging the battery"
        case (true, _, true):
            // Solar is up but not covering demand — the battery is topping up
            // the shortfall. Worth saying plainly; it's the case people
            // misread as "my solar is working, so why is the battery dropping".
            return "Solar running, battery covering the shortfall"
        case (true, _, _):
            if exporting { return "Solar powering the house and exporting" }
            return "Solar powering the house"
        case (false, true, _):
            return "Charging the battery"
        case (false, _, true):
            return "Running on battery"
        default:
            if importing { return "Drawing from the grid" }
            if exporting { return "Exporting to the grid" }
            return "System idle"
        }
    }

    // MARK: - Low-battery notifications
    //
    // Not in the GNOME original. Three escalating alerts, each firing only
    // while the battery is actually under load — a battery sitting at 19%
    // idle or on charge isn't a problem worth waking someone for.

    private enum BatteryAlert {
        /// SOC levels that each fire once per crossing, most severe last.
        static let levels = [24, 20, 18]

        /// Minimum draw for an alert to count as "actively being used".
        ///
        /// Specified as "higher than 100 kW", which cannot be what was meant:
        /// `inverterPower` for this system is 6 kW, so a 100 kW draw is 16x
        /// the hardware ceiling and no alert would ever fire. Read as 100 W.
        /// Also comfortably above the ±0.01 kW noise floor used elsewhere, so
        /// float-charge jitter can't register as a discharge.
        static let minDrawKW = 0.1

        /// How far back above a level the SOC must climb before that level can
        /// fire again. Without it, a battery hovering at 23.5% re-fires the 24%
        /// alert every time it ticks across the boundary.
        static let rearmMargin = 2

        /// SOC below which the battery is drawn as 🪫 instead of 🔋.
        ///
        /// Kept separate from `levels` on purpose: this is a display threshold
        /// ("less than 25%") and those are alert thresholds. They are adjacent
        /// numbers but not the same decision, so changing one must not silently
        /// move the other. Note it is also *not* the adaptive panel's 25% slot
        /// threshold, which has a dead band because swapping a whole metric is
        /// disruptive; swapping an icon is not, so this one is a plain compare.
        static let lowIconSOC = 25.0
    }

    /// 🪫 below `lowIconSOC`, 🔋 otherwise. Single source of truth for every
    /// place the battery is drawn.
    private func batteryIcon(for socPercent: Double) -> String {
        socPercent < BatteryAlert.lowIconSOC ? "🪫" : "🔋"
    }

    /// SF Symbol for the battery, stepped by charge and marked when charging.
    ///
    /// All names verified to resolve on this deployment target — a symbol that
    /// doesn't exist renders as an empty box with no build error, so these
    /// can't be edited casually.
    private func batterySymbol(for socPercent: Double, powerKW: Double) -> String {
        // No charging variant. SF Symbols only ships `battery.100percent.bolt`
        // — there is no .bolt at 25/50/75 — so using it while charging drew a
        // *full* battery beside the text "30%". The level is what sits next to
        // the number, so the level wins; charging is carried by the Battery
        // row's own words ("Charging 1.50 kW") and by the icon being lit
        // rather than dimmed.
        switch socPercent {
        case ..<10:  return "battery.0percent"
        case ..<38:  return "battery.25percent"
        case ..<63:  return "battery.50percent"
        case ..<88:  return "battery.75percent"
        default:     return "battery.100percent"
        }
    }

    /// Fires at most one notification per poll, for the most severe level newly
    /// crossed. Levels crossed in the same jump are marked as seen rather than
    /// notified, so a fast 30% -> 17% drop produces one "18%" alert instead of
    /// three notifications at once.
    private func checkBatteryAlerts(batterySOC: Double, batteryPowerKW: Double, stationName: String) {
        // Negative batteryPowerV2 is discharge; flip it so drawKW reads as a
        // magnitude, matching the "power being drawn from it" phrasing.
        let drawKW = -batteryPowerKW

        // Re-arm levels the battery has recovered clear of. Done regardless of
        // load, so a battery that recharges while idle is armed again for the
        // next discharge cycle.
        for level in BatteryAlert.levels
        where batterySOC >= Double(level + BatteryAlert.rearmMargin) {
            firedBatteryAlerts.remove(level)
        }

        guard drawKW > BatteryAlert.minDrawKW else { return }

        let crossed = BatteryAlert.levels.filter {
            batterySOC < Double($0) && !firedBatteryAlerts.contains($0)
        }
        guard let severest = crossed.min() else { return }

        firedBatteryAlerts.formUnion(crossed)

        Notifier.shared.notify(
            title: "🪫 Solis Battery Below \(severest)%",
            body: "Battery for \(stationName) is at \(jsNum(batterySOC))% and discharging at "
                + "\(toFixed(drawKW, 2)) kW."
        )
    }

    // MARK: - Adaptive panel mode
    //
    // Not in the GNOME original. The menu bar has room for two metrics, and
    // in the ported modes one of them is solar — which reads a constant
    // "0.00 kW" for roughly half of every day. Adaptive mode gives each slot
    // to whichever metric currently carries information:
    //
    //   slot 1  solar, or home load once solar has gone quiet (i.e. at night)
    //   slot 2  battery %, or grid once the battery is low AND not the thing
    //           currently supplying the house
    //
    // Slot 2's rule is deliberately *not* a plain "SOC <= 25 -> show grid":
    // a low battery that is still discharging is the number most worth
    // watching, so it keeps the slot. It yields only when something else is
    // carrying the load and the grid becomes the more informative reading.

    private enum Adaptive {
        /// Below this, power is indistinguishable from noise. Same ±0.01 kW
        /// floor the Charging/Discharging labels and the flow diagram use;
        /// named here because the adaptive rules reference it repeatedly.
        /// The existing literals elsewhere in this file are left as they are
        /// — deduplicating those is a separate change, not part of this one.
        static let powerFloor = 0.01
        /// Solar must clear this, not merely the floor, to take its slot
        /// back. Without the gap, a dawn/dusk reading hovering around the
        /// floor swaps the panel on every single poll.
        static let solarWake = 0.05
        /// Battery yields its slot at or below this state of charge...
        static let socLow = 25.0
        /// ...and reclaims it at or above this one. The gap is the dead band
        /// that stops a battery parked at exactly 25% from oscillating.
        static let socRestore = 30.0
        /// How long a swap condition must hold before the panel changes —
        /// expressed in **seconds, not polls**. This was originally a flat
        /// "2 consecutive polls", which is a bug: refresh-interval is user
        /// configurable up to 3600 s, so at a real-world 240 s interval that
        /// same constant meant a sunset swap took 8 minutes and looked to the
        /// user like the panel had frozen. Confirmation has to be a duration
        /// so behaviour doesn't scale with the poll rate.
        static let confirmWindow = 120.0
    }

    /// `confirmWindow` converted to a poll count at the current refresh rate.
    ///
    /// Floored at 1: when the interval is already longer than the window,
    /// consecutive samples are further apart in time than the window itself,
    /// so a single sample is all the confirmation the window was ever asking
    /// for. Demanding two would just add a full interval of dead time.
    private var confirmPolls: Int {
        let interval = Double(max(10, settings.refreshInterval))
        return max(1, Int((Adaptive.confirmWindow / interval).rounded()))
    }

    /// Decides what each adaptive slot shows, with hysteresis on both.
    private func updateAdaptiveSlots(pvPower: Double, batterySOC: Double, batteryPowerKW: Double) {
        // Slot 1. Solar reclaims the slot as soon as it clears solarWake;
        // giving it up requires confirmPolls consecutive samples at or below
        // the noise floor. Readings in between hold the current slot rather
        // than counting toward a swap, so trickle output doesn't drift the
        // counter upward over a long dim afternoon.
        var wantLoad = adaptiveShowingLoad
        if pvPower > Adaptive.solarWake {
            wantLoad = false
            solarSlotPendingPolls = 0
        } else if pvPower <= Adaptive.powerFloor {
            solarSlotPendingPolls += 1
            if solarSlotPendingPolls >= confirmPolls { wantLoad = true }
        } else {
            solarSlotPendingPolls = 0
        }

        // Slot 2. Grid takes over only while the battery is low *and* not
        // being drawn from. The threshold it's compared against depends on
        // which metric is currently showing — that asymmetry is the dead band.
        let batteryLow = adaptiveShowingGrid
            ? batterySOC < Adaptive.socRestore
            : batterySOC <= Adaptive.socLow
        let discharging = batteryPowerKW < -Adaptive.powerFloor
        let wantGrid = batteryLow && !discharging

        // First real sample: adopt both answers outright. Otherwise the panel
        // would open on whatever the initial state happens to be and take
        // confirmPolls to correct itself.
        guard adaptiveSeeded else {
            adaptiveSeeded = true
            adaptiveShowingLoad = pvPower <= Adaptive.powerFloor
            adaptiveShowingGrid = wantGrid
            solarSlotPendingPolls = 0
            gridSlotPendingPolls = 0
            return
        }

        adaptiveShowingLoad = wantLoad

        if wantGrid == adaptiveShowingGrid {
            gridSlotPendingPolls = 0
        } else {
            gridSlotPendingPolls += 1
            if gridSlotPendingPolls >= confirmPolls {
                adaptiveShowingGrid = wantGrid
                gridSlotPendingPolls = 0
            }
        }
    }

    /// Grid reading for the panel: magnitude plus an import/export arrow.
    ///
    /// Power only — never grid *status*. "Grid Offline / Fault" comes from
    /// data.state, whose non-1 values are not understood (a live sample read
    /// state=3 while solar was generating normally with zero alarms). A false
    /// fault warning pinned permanently in the menu bar would be considerably
    /// worse than the same label inside the popup, so the panel stays out of
    /// it until state is actually mapped.
    private func gridPanelText(_ gridKW: Double) -> String {
        // ±0.005 matches the Importing/Exporting/Balanced thresholds the Grid
        // card uses, so panel and popup can never disagree about direction.
        // powerText for the same reason — it is what the Grid card now uses,
        // so one reading can't print two ways. (This is the adaptive mode
        // only; compact/full/minimal keep GNOME's "0.00 kW" for parity.)
        // powerText carries its own unit — no " kW" suffix here. The arrow uses
        // the same floor as the window's Grid row, so panel and popup can't
        // disagree about whether power is moving. The icon is supplied by the
        // segment, so this returns text only.
        gridText(gridKW)
    }

    // MARK: - Error states

    private func showError(_ message: String) {
        panelText = "☀️ Solis (\(message))"
        panelImage = renderPanelImage([PanelSegment(symbol: "exclamationmark.triangle.fill", text: message)])
        display.badgeText = message
        display.badgeOnline = false
        // The hero keeps its last good reading rather than blanking to zero —
        // a stale number the status line has flagged as stale is more useful
        // than a confident 0.00 kW that looks like a real measurement.
        display.statusOK = false
        display.statusLine = message
    }

    /// Missing setup, which is not the same as an expired session: no amount of
    /// signing in supplies a signing secret.
    private func showNotConfigured() {
        stopTimer()
        panelText = "⚙️ Solis — not configured"
        panelImage = renderPanelImage([PanelSegment(symbol: "gearshape.fill", text: "Not configured")])
        display.statusOK = false
        display.statusLine = "Signing secret or station ID not set — see the README"
        NSLog("%@", "SolisSolarMonitor: api-signing-secret or station-id is unset; "
            + "set both with `defaults write com.faizan.SolisSolarMonitor …`")
    }

    private func showSessionExpired() {
        // Stop polling to avoid flooding, exactly as _showSessionExpired does.
        stopTimer()
        sessionExpired = true
        panelText = "🔑 Session Expired — Click to fix"
        panelImage = renderPanelImage([PanelSegment(symbol: "key.fill", text: "Session Expired")])
        display.badgeText = "Session Expired"
        display.badgeOnline = false
        display.timestamp = "Tokens expired — open Preferences to update"
        display.statusOK = false
        display.statusLine = "Session expired"
        NSLog("SolisSolarMonitor: Session expired. Open Preferences and log in again to refresh tokens.")
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        let interval = max(10, settings.refreshInterval)
        let timer = Timer(timeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.fetchSolarData() }
        }
        // .common so polling continues while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func restartTimer() {
        stopTimer()
        startTimer()
    }
}
