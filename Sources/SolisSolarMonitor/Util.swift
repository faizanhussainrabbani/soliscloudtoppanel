import Foundation
import SwiftUI

// ---------------------------------------------------------------------------
// JS-compatible number formatting
//
// The GNOME extension interpolates raw numbers into template strings
// (e.g. `${co2} t CO₂`), which uses JavaScript's Number->String rules.
// This reproduces that so the macOS output is character-identical.
// ---------------------------------------------------------------------------
func jsNum(_ d: Double) -> String {
    if !d.isFinite { return "0" }
    if d == d.rounded() && abs(d) < 1e15 {
        return String(Int64(d))
    }
    var s = String(format: "%.10f", d)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}

/// Equivalent of JS `Number.prototype.toFixed(n)`.
func toFixed(_ d: Double, _ places: Int) -> String {
    String(format: "%.\(places)f", d.isFinite ? d : 0)
}

// ---------------------------------------------------------------------------
// Loose JSON access
//
// Mirrors the JS `data.foo !== undefined ? data.foo : fallback` pattern.
// SolisCloud is inconsistent about returning numbers vs numeric strings,
// so both are accepted.
// ---------------------------------------------------------------------------
struct JSONDict {
    let raw: [String: Any]

    init(_ raw: [String: Any]) { self.raw = raw }

    func num(_ key: String) -> Double? {
        switch raw[key] {
        case let n as NSNumber: return n.doubleValue
        case let s as String:   return Double(s)
        default:                return nil
        }
    }

    func str(_ key: String) -> String? {
        switch raw[key] {
        case let s as String:   return s
        case let n as NSNumber: return n.stringValue
        default:                return nil
        }
    }

    func flag(_ key: String) -> Bool {
        switch raw[key] {
        case let b as Bool:     return b
        case let n as NSNumber: return n.boolValue
        case let s as String:   return !s.isEmpty && s != "false" && s != "0"
        default:                return false
        }
    }

    func dict(_ key: String) -> JSONDict? {
        (raw[key] as? [String: Any]).map(JSONDict.init)
    }

    /// An array of nested objects — the alarm list's `records`.
    func array(_ key: String) -> [JSONDict]? {
        guard let raw = raw[key] as? [Any] else { return nil }
        return raw.compactMap { ($0 as? [String: Any]).map(JSONDict.init) }
    }

    /// True when the key is present and non-null, matching JS `!== undefined`.
    func has(_ key: String) -> Bool {
        guard let v = raw[key] else { return false }
        return !(v is NSNull)
    }
}

// ---------------------------------------------------------------------------
// Colors lifted from stylesheet.css
//
// stylesheet.css was written for GNOME Shell's popup, which is always dark,
// so these hexes were only ever tuned against a dark background. A
// MenuBarExtra follows the system appearance, and several of them fail
// WCAG AA (4.5:1) against a light background — e.g. solisSolar is 1.47:1 on
// white. The card-title colors are dynamic pairs, picked so each variant
// clears 4.5:1 against its own background; the badge colors keep white text
// on a saturated fill in both modes, so they didn't need one.
// ---------------------------------------------------------------------------
extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue:  Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }

    /// A color that swaps hex values with the system appearance, rather than
    /// one hex tinted by opacity — opacity alone can't fix a contrast
    /// failure, since it moves the color toward the very background it's
    /// failing against.
    init(light: UInt32, dark: UInt32) {
        self.init(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green:   CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue:    CGFloat(hex & 0xFF) / 255.0,
                alpha: 1.0
            )
        })
    }

    // .solis-solar-color — original #f6d32d is 1.47:1 on white (fails badly).
    // Text needs WCAG's 4.5:1 (1.4.3), which for a hue this light forces a
    // dark olive — there's no way to keep it looking "yellow" at that ratio.
    static let solisSolar   = Color(light: 0x8c7406, dark: 0xf6d32d)
    // .solis-battery-color — original #3584e4 is 3.77:1 on white (fails)
    static let solisBattery = Color(light: 0x1e75df, dark: 0x3986e5)
    // .solis-load-color — original #ff7800 is 2.65:1 on white (fails)
    static let solisLoad    = Color(light: 0xbd5900, dark: 0xff7800)
    // .solis-grid-color was Adwaita purple (#9141ac / #b06bc7). Purple carries
    // no association with mains electricity — it was inherited identity, not
    // meaning, and it read as the most decorative colour on screen. Teal is
    // the utility/infrastructure convention, and it stays clearly distinct
    // from the battery's blue at the small sizes these symbols are drawn at.
    static let solisGrid    = Color(light: 0x0d7d78, dark: 0x3fc9bd)

    // solisSolarGraphic lived here: a more vivid gold for decorative shapes,
    // which only need WCAG's 3:1 non-text ratio rather than the 4.5:1 that
    // forces solisSolar into olive. Its only users were the flow diagram's
    // rings and edges, so it went when the diagram did.

    /// The "not happening right now" ink for dimmed icons.
    ///
    /// Not `.secondary`: on white that resolves to a light grey, so in light
    /// mode a dimmed icon nearly vanished and the lit/dimmed distinction — the
    /// window's one piece of colour semantics — stopped reading. This is
    /// noticeably darker in light mode and close to `.secondary` in dark, where
    /// the original was already right.
    static let solisDim     = Color(light: 0x53565c, dark: 0x8b8f96)

    /// Amber, for "the app is fine but the data isn't fresh". Distinct from
    /// solisOffline: a failed fetch and a silent inverter are different
    /// problems with different fixes, and red for both would flatten that.
    static let solisWarning = Color(light: 0x9a5b00, dark: 0xf5a623)

    static let solisOnline  = Color(hex: 0x2ec27e)  // .solis-badge-online
    static let solisOffline = Color(hex: 0xe01b24)  // .solis-badge-offline
}

// ---------------------------------------------------------------------------
// HTTP date header — equivalent of JS `new Date().toUTCString()`
// ---------------------------------------------------------------------------
enum HTTPDate {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return f
    }()

    static func now() -> String { formatter.string(from: Date()) }
}

/// Fallback timestamp for when the API omits dataTimestampStr. Matches the
/// shape SolisCloud sends, e.g. "02/08/2026 20:45:01 (UTC+05:00)", so the
/// header reads the same either way.
func fullLocalTimestamp() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    // "xxx" rather than "ZZZZZ": the latter collapses a zero offset to "Z".
    f.dateFormat = "dd/MM/yyyy HH:mm:ss '(UTC'xxx')'"
    return f.string(from: Date())
}

// ---------------------------------------------------------------------------
// Power formatting for the redesigned window (and the adaptive panel mode).
// ---------------------------------------------------------------------------

/// A power reading as kilowatts, always, to two decimals.
///
/// This exists because the summary tiles put Solar, Battery and Grid side by
/// side, and the old per-card formats didn't agree — Solar printed "0.00 kW"
/// next to Grid's "0.000 kW", which reads as a bug rather than as extra
/// precision. Consistency was the real problem, so this is the one place the
/// format is decided.
///
/// An earlier version switched to watts below 1 kW. It was rejected, rightly:
/// a hero number whose unit changes between midday and midnight can't be
/// compared against itself at a glance, and the mixed units read as noisier
/// than the precision was worth. One unit, one number of decimals, everywhere.
///
/// The cost is accepted knowingly: grid readings are often small, so a 0.146 kW
/// import now prints "0.15 kW". The exact figure is still available in the
/// diagnostics if it is ever wanted.
///
/// Deliberately NOT used by the ported compact/full/minimal panel modes: those
/// are byte-for-byte GNOME parity and format their own values.
func powerText(_ kW: Double) -> String {
    "\(toFixed(kW, 2)) kW"
}

// ---------------------------------------------------------------------------
// Sunrise / sunset
//
// SolisCloud returns latitude and longitude with the station but no sun times,
// so these are computed. The NOAA approximation is good to about a minute at
// these latitudes — checked against published times for London and Sydney, and
// hand-verified for Karachi (solar noon 12:36 PKT, half-day 6h30m on 15 Aug,
// giving 06:06 / 19:06 against the computed 06:05 / 19:07).
// ---------------------------------------------------------------------------

/// Sunrise and sunset for a location and date, or nil inside a polar day or
/// night where the sun never crosses the horizon.
func sunTimes(latitude: Double, longitude: Double, date: Date = Date()) -> (rise: Date, set: Date)? {
    let rad = Double.pi / 180
    let julianDay = date.timeIntervalSince1970 / 86400.0 + 2440587.5
    let n = (julianDay - 2451545.0 + 0.0008).rounded()

    let meanSolarNoon = n - longitude / 360.0
    let meanAnomaly = (357.5291 + 0.98560028 * meanSolarNoon).truncatingRemainder(dividingBy: 360)
    let center = 1.9148 * sin(meanAnomaly * rad)
        + 0.0200 * sin(2 * meanAnomaly * rad)
        + 0.0003 * sin(3 * meanAnomaly * rad)
    let eclipticLongitude = (meanAnomaly + center + 180 + 102.9372)
        .truncatingRemainder(dividingBy: 360)
    let transit = 2451545.0 + meanSolarNoon
        + 0.0053 * sin(meanAnomaly * rad)
        - 0.0069 * sin(2 * eclipticLongitude * rad)

    let sinDeclination = sin(eclipticLongitude * rad) * sin(23.44 * rad)
    let cosDeclination = cos(asin(sinDeclination))
    // -0.833° is the standard horizon dip plus atmospheric refraction.
    let cosHourAngle = (sin(-0.833 * rad) - sin(latitude * rad) * sinDeclination)
        / (cos(latitude * rad) * cosDeclination)
    guard cosHourAngle >= -1, cosHourAngle <= 1 else { return nil }

    let hourAngle = acos(cosHourAngle) / rad
    // Not named `date` — that shadows this function's own `date` parameter for
    // the whole scope, and the earlier lines then fail to compile.
    func dateFromJulian(_ j: Double) -> Date {
        Date(timeIntervalSince1970: (j - 2440587.5) * 86400.0)
    }
    return (dateFromJulian(transit - hourAngle / 360.0),
            dateFromJulian(transit + hourAngle / 360.0))
}

/// An energy total with its unit, always to two decimals.
///
/// It briefly dropped the decimals on whole values — SolisCloud returns
/// `dayEnergy` as exactly `9` when it is 9, and "9.00 kWh" claims four
/// significant figures for a number that has one. That reasoning is sound in
/// isolation and wrong in a column.
///
/// The Details section stacks Solar, Used and Bought from grid in the same
/// unit specifically so they can be compared. With the rule applied, that read:
///
///     Solar               9 kWh
///     Used             9.29 kWh
///     Bought from grid 1.29 kWh
///
/// and solar looked like the approximate one — a rounded figure beside two
/// precise ones — when in fact all three are equally good. Values presented for
/// comparison have to share a format; a format that varies per value encodes a
/// difference in confidence that isn't there.
///
/// So: two decimals, everywhere this is used. Don't reintroduce the
/// whole-number case without checking what it sits next to.
func energyText(_ value: Double, _ unit: String) -> String {
    "\(toFixed(value, 2)) \(unit)"
}

/// The same reading split for the hero, which sets the number and its unit at
/// different sizes. Returns e.g. ("490", "W") or ("2.40", "kW").
func powerParts(_ kW: Double) -> (value: String, unit: String) {
    let text = powerText(kW)
    let pieces = text.split(separator: " ")
    guard pieces.count == 2 else { return (text, "") }
    return (String(pieces[0]), String(pieces[1]))
}
