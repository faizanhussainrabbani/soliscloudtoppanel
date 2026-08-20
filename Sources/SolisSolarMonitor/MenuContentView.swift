import SwiftUI
import AppKit

/// Port of _buildPopupMenu() / stylesheet.css.
struct MenuContentView: View {
    @ObservedObject var monitor: SolisMonitor
    @ObservedObject var settings: SolisSettings

    /// Details start expanded when the Advanced Information preference is on,
    /// but can be folded away for this viewing without changing the setting.
    /// MenuBarExtra rebuilds this view each time the window opens, so the
    /// preference is what it returns to — which is the intended behaviour.
    @State private var showDetails: Bool?

    /// Details start closed. They used to default from the Advanced
    /// Information preference, which no longer exists.
    private var detailsOpen: Bool { showDetails ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {   // .solis-popup-container
            statusLine
            hero
            statStrip

            detailsToggle
            if detailsOpen {
                metricsList
            }

            if monitor.sessionExpired {
                sessionExpiredBanner
            }

            Divider().opacity(0.5)
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: - Status line
    //
    // Only shown when something is wrong.
    //
    // This row has shrunk twice, both times by removing what carried no
    // information. It began as the ported header: bold station title, full
    // timestamp, and a green "Connected" pill, three elements standing between
    // the reader and the first number. Then the timestamp moved into Details
    // and the pill became a dot. Now the station name goes too — there is one
    // station, so naming it every time says nothing — and the dot with it,
    // since a permanently green light is only informative on the day it isn't
    // green.
    //
    // What remains is the failure message, which appears from nothing. The
    // healthy window opens directly on the hero, and anything in this position
    // means something needs attention.

    @ViewBuilder
    private var statusLine: some View {
        // Two different problems, ranked. A failed fetch means these numbers
        // are whatever we last had; a stale feed means the fetch worked and the
        // inverter went quiet. The fetch failure is the more serious of the
        // two, so it wins the row if somehow both are true.
        if !monitor.display.statusOK {
            warningRow(monitor.display.statusLine, color: .solisOffline,
                       symbol: "exclamationmark.triangle.fill")
        } else if let alarm = monitor.display.alarmSummary {
            // An active alarm outranks stale data: a grid outage is a fact
            // about the house, not about the feed.
            warningRow(alarm, color: .solisOffline,
                       symbol: monitor.display.gridOutage ? "bolt.slash.fill" : "exclamationmark.triangle.fill")
        } else if let age = monitor.display.dataAgeText {
            warningRow(age, color: .solisWarning, symbol: "clock.badge.exclamationmark.fill")
        }
    }

    private func warningRow(_ message: String, color: Color, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Hero
    //
    // Design direction A: one number leads. Which number that is comes from
    // the monitor (the same choice the menu bar's first slot makes), never
    // from a second test here.

    /// Two explicit sizes, not a continuous scale. With Details closed the
    /// hero is the whole point of the window and gets the full 48pt. With
    /// Details open the reader has asked for the full table, so the hero steps
    /// back to a heading — still the largest thing on screen, but no longer
    /// pushing four detail rows and a diagram down the window.
    private var heroSize: (value: CGFloat, unit: CGFloat) {
        detailsOpen ? (32, 14) : (48, 18)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(monitor.display.heroLabel.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(monitor.display.heroValue)
                    .font(.system(size: heroSize.value, weight: .light))
                    .monospacedDigit()
                    .lineLimit(1)
                    // .fixedSize, never .minimumScaleFactor. The size change
                    // below is a deliberate two-step, not a licence for
                    // SwiftUI to scale the text down whenever the window gets
                    // tall — which is what the earlier version did, silently
                    // rendering the same reading a third smaller with Details
                    // open and no way to predict when.
                    .fixedSize()
                Text(monitor.display.heroUnit)
                    .font(.system(size: heroSize.unit, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Text(monitor.display.heroCaption)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    // MARK: - Stat strip (the three metrics the hero isn't showing)

    /// Colour when the metric is live, secondary when it's at zero.
    ///
    /// One rule for every icon in the window: a full-strength glyph beside a
    /// 0.00 kW reading is the icon contradicting the number next to it, and
    /// that was true of Grid at balance and Battery at idle just as much as it
    /// was of Solar at night. Dimming makes colour mean "this is happening".
    private func tint(_ color: Color, live: Bool) -> Color {
        live ? color : .solisDim
    }

    private var statStrip: some View {
        HStack(spacing: 8) {
            if monitor.display.heroIsSolar {
                StatTile(symbol: "house",
                         symbolColor: tint(.solisLoad, live: !monitor.display.loadIdle),
                         key: "Home", value: monitor.display.loadPower,
                         valueDimmed: monitor.display.loadIdle)
            } else {
                StatTile(symbol: "sun.max.fill",
                         symbolColor: tint(.solisSolar, live: !monitor.display.solarAsleep),
                         key: "Solar", value: monitor.display.pvPower,
                         valueDimmed: monitor.display.solarAsleep)
            }
            // The battery is the one tile allowed to colour its *value*, and
            // only when low. That is colour used semantically — "this needs
            // attention" — rather than as a category label, which is what the
            // four coloured titles were doing before. Low beats idle: a battery
            // that is low but resting still wants your attention.
            StatTile(symbol: monitor.display.batterySymbol,
                     accessorySymbol: monitor.display.batteryCharging ? "bolt.fill" : nil,
                     symbolColor: monitor.display.batteryLow
                         ? .solisOffline
                         : tint(.solisBattery, live: !monitor.display.batteryIdle),
                     key: "Battery", value: monitor.display.batterySOC,
                     valueColor: monitor.display.batteryLow ? .solisOffline : nil)
            StatTile(symbol: "powerplug.fill",
                     symbolColor: tint(.solisGrid, live: !monitor.display.gridIdle),
                     key: "Grid", value: monitor.display.gridPower,
                     valueDimmed: monitor.display.gridIdle)
            // The battery's value is deliberately never dimmed. A zero power
            // reading means nothing is happening; a state of charge is never
            // "nothing", so 95% stays legible even when the battery is resting.
            // Its icon still dims, because that reflects flow.
        }
    }

    // MARK: - Details disclosure

    private var detailsToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { showDetails = !detailsOpen }
        } label: {
            HStack(spacing: 4) {
                Text(detailsOpen ? "Hide details" : "Details")
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .rotationEffect(.degrees(detailsOpen ? 180 : 0))
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(detailsOpen ? "Hide details" : "Show details")
    }

    // MARK: - Metrics (borderless list — labels and a hero number per row,
    // no card chrome, in the spirit of Tesla's energy-app UI rather than the
    // boxed 2x2 grid this replaced)

    /// Supporting facts — deliberately *not* a second copy of the hero and the
    /// tiles. Every row here is something the summary above can't show, so
    /// opening Details adds information rather than repeating it.
    ///
    /// One row style, shared with the diagnostics section below it, at a type
    /// size clearly under the tiles'. The previous version used a second
    /// layout whose values were 17pt bold against the tiles' 14pt semibold, so
    /// the content you had to click to reveal outshouted the summary that was
    /// always on screen.
    private var metricsList: some View {
        VStack(spacing: 0) {
            // Grouped by time horizon, not by subsystem.
            //
            // It used to be solar / grid / battery, which is where the data
            // comes from rather than what the reader is asking. That mixed
            // tenses inside every group — Sunset (a future event) sat among
            // today's totals, and "Battery Idle" (now) sat beside "On battery
            // until 01:17" (a projection) because both were "about the
            // battery". Each group now answers exactly one question, and the
            // conditional rows have an obvious home rather than needing a
            // judgement call each time one is added.
            //
            // A side benefit: under a TODAY heading the labels stop repeating
            // the word. "Bought from grid today" became "Bought from grid".

            SectionHeading("Today")
            DiagnosticRow(symbol: "sun.max.fill",
                          symbolColor: tint(.solisSolar, live: !monitor.display.solarTodayZero),
                          label: "Solar", value: monitor.display.solarTodayText)
            DiagnosticRow(symbol: "house",
                          symbolColor: tint(.solisLoad, live: !monitor.display.usedTodayZero),
                          label: "Used", value: monitor.display.usedTodayText)
            DiagnosticRow(symbol: "cart.fill",
                          symbolColor: tint(.solisGrid, live: !monitor.display.gridBoughtZero),
                          label: "Bought from grid", value: monitor.display.gridBoughtTodayText)
            DiagnosticRow(symbol: "banknote.fill",
                          symbolColor: tint(.solisGrid, live: !monitor.display.gridBoughtZero),
                          label: "Cost", value: monitor.display.gridCostTodayText)
            // Daytime: the forecast prospect. After dark: what came of it.
            if let sunToday = monitor.display.sunTodayComparison {
                DiagnosticRow(symbol: "cloud.sun.fill", symbolColor: .solisSolar,
                              label: "Sunshine", value: sunToday)
            }
            if let comparison = monitor.display.solarComparisonText {
                DiagnosticRow(symbol: "chart.line.uptrend.xyaxis", symbolColor: .solisDim,
                              label: "Vs average", value: comparison)
            }

            if aheadHasContent {
                SectionHeading("Ahead")
                if let peak = monitor.display.peakWindowText {
                    DiagnosticRow(symbol: "chart.bar.fill",
                                  symbolColor: tint(.solisSolar, live: monitor.display.peakWindowLive),
                                  label: monitor.display.peakWindowLabel, value: peak)
                }
                if let sunTime = monitor.display.sunTimeText {
                    DiagnosticRow(symbol: monitor.display.sunLabel == "Sunset" ? "sunset.fill" : "sunrise.fill",
                                  symbolColor: .solisSolar,
                                  label: monitor.display.sunLabel, value: sunTime)
                }
                if let end = monitor.display.batteryEndTimeText {
                    DiagnosticRow(symbol: "clock.arrow.circlepath", symbolColor: .solisBattery,
                                  label: monitor.display.batteryEndLabel, value: end)
                } else if monitor.display.batteryCapacityUnset {
                    DiagnosticRow(symbol: "clock.arrow.circlepath", symbolColor: .solisDim,
                                  label: "Time remaining", value: "Set capacity in Preferences")
                }
            }

            SectionHeading("Equipment")
            DiagnosticRow(symbol: monitor.display.batterySymbol,
                          accessorySymbol: monitor.display.batteryCharging ? "bolt.fill" : nil,
                          symbolColor: monitor.display.batteryLow
                              ? .solisOffline
                              : tint(.solisBattery, live: !monitor.display.batteryIdle),
                          label: "Battery", value: monitor.display.batteryFlowText)
            if let temp = monitor.display.inverterTempText {
                DiagnosticRow(symbol: "thermometer.medium",
                              symbolColor: monitor.display.inverterTempHot ? .solisWarning : .solisDim,
                              label: "Inverter", value: temp)
            }
            // Equipment health, which is where an alarm belongs — it was
            // previously filed under the battery group for want of anywhere
            // better.
            if let detail = monitor.display.alarmDetail {
                DiagnosticRow(symbol: "exclamationmark.triangle.fill", symbolColor: .solisOffline,
                              label: monitor.display.gridOutage ? "Grid" : "Alarm", value: detail)
            }

            // The reading's own timestamp: metadata about the whole panel
            // rather than a fact about the system, so it stays ungrouped and
            // last. Kept at .secondary rather than the original .tertiary 9pt,
            // which was too faint to read.
            HStack {
                Text(monitor.display.timestamp)
                    .font(.system(size: 9.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
        }
    }

    /// True unless every forward-looking row is absent — otherwise a station
    /// with no coordinates and no forecast would show a bare "Ahead" heading.
    private var aheadHasContent: Bool {
        monitor.display.peakWindowText != nil
            || monitor.display.sunTimeText != nil
            || monitor.display.batteryEndTimeText != nil
            || monitor.display.batteryCapacityUnset
    }

    // MARK: - Session expired

    /// GNOME turned the whole panel button into a one-shot "click to open
    /// prefs" target. A MenuBarExtra click always opens its window instead,
    /// so the same affordance lives here as an explicit button.
    private var sessionExpiredBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .foregroundStyle(Color.solisOffline)
            Text("Session expired — log in again to refresh tokens.")
                .font(.system(size: 10))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.solisOffline.opacity(0.18))
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Preferences…") { PreferencesWindow.show() }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .font(.system(size: 11))
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

/// One of the three compact readings under the hero.
///
/// Deliberately quiet: a soft fill rather than a border, the category name in
/// small caps carrying the only colour, and the value at a size that reads as
/// clearly subordinate to the hero. If these grew to compete with the hero the
/// window would be back to four equal metrics with extra chrome.
private struct StatTile: View {
    let symbol: String
    var accessorySymbol: String? = nil
    let symbolColor: Color
    let key: String
    let value: String
    /// Set only to flag a state worth noticing; nil leaves the value neutral.
    var valueColor: Color? = nil
    /// Dims the number as well as the icon, for a power reading sitting at
    /// zero. Half-applying the rule left whispering icons above shouting
    /// numbers; dimming both also makes the one live tile stand out, which the
    /// icon alone never achieved.
    var valueDimmed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                HStack(spacing: 1) {
                    Image(systemName: symbol)
                        .font(.system(size: 9))
                    // Same charging bolt the menu bar draws, for the same
                    // reason: no SF Symbol carries level and charging together
                    // below 100%.
                    if let accessory = accessorySymbol {
                        Image(systemName: accessory)
                            .font(.system(size: 6.5))
                    }
                }
                .foregroundStyle(symbolColor)
                Text(key.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? (valueDimmed ? Color.solisDim : .primary))
                .lineLimit(1)
                // No minimumScaleFactor — the same mechanism that silently
                // resized the hero. A value too wide for a tile should be a
                // visible layout problem, not a quietly shrunk number.
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(key) \(value)")
    }
}

/// The window's one row style, used by every row in the Details section.
///
/// Colour lives on the symbol and nowhere else. Previously four saturated hues
/// coloured the row *titles*, which made colour a category label — a job the
/// words were already doing — and turned the expanded window into a rainbow.
/// Weather's model is the one followed here: a coloured glyph against neutral
/// text, so colour can mean something when it does appear.
private struct DiagnosticRow: View {
    let symbol: String
    /// A smaller glyph tight against the main one — the charging bolt, matching
    /// the summary tile so one state isn't drawn two ways.
    var accessorySymbol: String? = nil
    var symbolColor: Color = .secondary
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 1) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5))
                if let accessorySymbol {
                    Image(systemName: accessorySymbol)
                        .font(.system(size: 7.5))
                }
            }
            .foregroundStyle(symbolColor)
            .frame(width: 20, alignment: .leading)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 4.5)
    }
}

/// Hairline separator between groups of facts.
private struct SectionRule: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 8)
    }
}

/// A group heading in the Details section.
///
/// Small caps in the secondary ink, matching the hero's label treatment so the
/// window has one typographic system rather than two. These exist because the
/// grouping now carries meaning — what happened, what's coming, what the
/// hardware is doing — and a hairline rule alone can separate rows without
/// saying why they belong together.
private struct SectionHeading: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.7)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 11)
        .padding(.bottom, 3)
    }
}
