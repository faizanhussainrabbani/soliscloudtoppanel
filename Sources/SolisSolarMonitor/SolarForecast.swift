import Foundation

/// Today's best production window, from a weather forecast.
///
/// The question this answers is "when should I run the heavy loads today",
/// which sun geometry alone cannot: the sun's path is near-identical from one
/// day to the next, so anything computed offline would print the same window
/// every day and ignore the clouds that actually decide the answer. This uses
/// forecast irradiance instead, so the window moves with the weather.
///
/// Open-Meteo: free, no API key, no account. The only thing sent is the
/// station's latitude and longitude.
enum SolarForecast {

    /// How long a window to look for. Fixed rather than derived.
    ///
    /// The obvious alternative — "the span where irradiance stays above 85% of
    /// today's peak" — was tried against three days of real forecast and fails
    /// exactly when it matters. On a flat, hazy day the peak is low, so 85% of
    /// it is a wide band: 19 August returned 09:30–15:45, announcing six hours
    /// of "peak" output on the worst of the three days. A fixed window can't
    /// mislead that way; it always names the best three hours there are, and
    /// the share it holds says how good those hours are.
    static let windowHours = 3.0

    struct Window {
        /// Absolute instants, so "has it started / is it over" is answered
        /// against real time rather than by comparing clock strings. The forecast
        /// is in the *station's* timezone, which need not be the Mac's.
        let start: Date
        let end: Date
        let startText: String   // "12:00", station local
        let endText: String     // "15:00"
        /// Fraction of the day's total irradiance falling inside the window.
        /// ~0.39 on a clear day, ~0.35 on a flat one — a rough concentration
        /// signal, not a headline number.
        let share: Double
    }

    /// Everything one request yields.
    struct Forecast {
        let window: Window?
        /// Tomorrow's window, for the hours after today's has ended.
        let tomorrowWindow: Window?
        /// Today's forecast sun against the mean of the preceding days, as a
        /// percentage. +3 means today is 3% sunnier than the recent norm.
        ///
        /// Deliberately weather-against-weather. The tempting alternative —
        /// actual output against output modelled from irradiance — is not
        /// trustworthy here: this system is curtailed for much of every sunny
        /// day once the battery fills, so a modelled expectation reads ~50%
        /// low daily and would report a fault that isn't one. Comparing sun to
        /// sun sidesteps the modelling and the curtailment together.
        let dayVersusRecentPercent: Double?
        let recentDayCount: Int
    }

    private struct Response: Decodable {
        struct Minutely: Decodable {
            let time: [String]
            let shortwave_radiation: [Double?]
        }
        struct Daily: Decodable {
            let time: [String]
            let shortwave_radiation_sum: [Double?]
        }
        let minutely_15: Minutely
        let daily: Daily
        /// Needed to turn the station-local timestamps into absolute Dates.
        let utc_offset_seconds: Int
    }

    /// The slot pair the sliding window landed on, before it becomes a Window.
    /// Split out so the arithmetic can be tested without dates or networking.
    struct Slots: Equatable {
        let startTimestamp: String
        let lastSlotTimestamp: String
        let share: Double
    }

    /// nil on any failure — no network, a changed API, a station with no
    /// coordinates, or a day with no sun at all. The row is hidden rather than
    /// showing a stale or invented window.
    static func fetch(latitude: Double, longitude: Double) async -> Forecast? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "minutely_15", value: "shortwave_radiation"),
            URLQueryItem(name: "daily", value: "shortwave_radiation_sum"),
            // A week of history for the baseline, plus today. One request
            // serves both the peak window and the day comparison.
            URLQueryItem(name: "past_days", value: "7"),
            // Two days, so the evening can point at tomorrow's window instead
            // of showing nothing once today's has passed.
            URLQueryItem(name: "forecast_days", value: "2"),
            // Station-local times, not the Mac's. If the two ever differ, the
            // solar day belongs to the panels, not the laptop.
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(Response.self, from: data)

            // The daily arrays now run 7 past days + today + tomorrow, so
            // "today" is the second from last. Getting this wrong would be
            // quiet and wrong rather than broken: the window would describe
            // tomorrow while claiming to be today's.
            let days = decoded.daily.time
            guard days.count >= 2 else { return nil }
            let today = days[days.count - 2]
            let tomorrow = days[days.count - 1]

            // past_days applies to minutely_15 as well, so the 15-minute series
            // covers nine days. Filtering by date matters: without it the
            // sliding window would search the whole span and could pick its
            // "best three hours" out of last Tuesday.
            func windowFor(_ date: String) -> Window? {
                let slots = zip(decoded.minutely_15.time, decoded.minutely_15.shortwave_radiation)
                    .filter { $0.0.hasPrefix(date) }
                guard let best = bestSlots(times: slots.map(\.0), values: slots.map(\.1)) else { return nil }
                return window(from: best, utcOffsetSeconds: decoded.utc_offset_seconds)
            }

            // Tomorrow is excluded from the day comparison — it hasn't happened,
            // and including it would compare a forecast against a baseline that
            // now contains a different forecast.
            let comparison = dayComparison(
                dailyTotals: Array(decoded.daily.shortwave_radiation_sum.dropLast()))

            return Forecast(window: windowFor(today),
                            tomorrowWindow: windowFor(tomorrow),
                            dayVersusRecentPercent: comparison?.percent,
                            recentDayCount: comparison?.days ?? 0)
        } catch {
            NSLog("%@", "SolisSolarMonitor: solar forecast unavailable — \(error.localizedDescription)")
            return nil
        }
    }

    /// Slides a fixed-width window across the day and keeps the position
    /// holding the most irradiance. Separated from the fetch so it can be
    /// exercised against recorded forecasts without a network call.
    static func bestSlots(times: [String], values: [Double?]) -> Slots? {
        // Daylight only. Including the flat zero-filled night would let the
        // window drift into darkness on a day with almost no sun.
        let daylight = zip(times, values).compactMap { time, value -> (String, Double)? in
            guard let value, value > 0 else { return nil }
            return (time, value)
        }

        let slotsPerWindow = Int(windowHours * 4)   // 15-minute resolution
        guard daylight.count >= slotsPerWindow else { return nil }

        let readings = daylight.map(\.1)
        let total = readings.reduce(0, +)
        guard total > 0 else { return nil }

        var running = readings[..<slotsPerWindow].reduce(0, +)
        var bestSum = running
        var bestStart = 0
        for start in 1...(readings.count - slotsPerWindow) {
            running += readings[start + slotsPerWindow - 1] - readings[start - 1]
            if running > bestSum {
                bestSum = running
                bestStart = start
            }
        }

        return Slots(startTimestamp: daylight[bestStart].0,
                     lastSlotTimestamp: daylight[bestStart + slotsPerWindow - 1].0,
                     share: bestSum / total)
    }

    /// Today (the last entry) against the mean of the days before it.
    ///
    /// Today is excluded from its own baseline, for the same reason the
    /// generation comparison excludes it: an average that contains the value
    /// being measured is pulled toward it and flattens the difference.
    static func dayComparison(dailyTotals: [Double?]) -> (percent: Double, days: Int)? {
        let totals = dailyTotals.compactMap { $0 }
        guard totals.count >= 3, let today = totals.last else { return nil }
        let past = totals.dropLast().filter { $0 > 0 }
        guard past.count >= 2 else { return nil }

        let average = past.reduce(0, +) / Double(past.count)
        guard average > 0 else { return nil }
        return ((today - average) / average * 100, past.count)
    }

    /// Turns the chosen slots into absolute instants plus display strings.
    static func window(from slots: Slots, utcOffsetSeconds: Int) -> Window? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds)

        guard let start = formatter.date(from: slots.startTimestamp),
              let lastSlot = formatter.date(from: slots.lastSlotTimestamp),
              let startText = clock(from: slots.startTimestamp),
              let lastClock = clock(from: slots.lastSlotTimestamp)
        else { return nil }

        // The final slot is a 15-minute bucket: the window runs to the end of
        // it, not to its start.
        return Window(start: start,
                      end: lastSlot.addingTimeInterval(15 * 60),
                      startText: startText,
                      endText: add15Minutes(to: lastClock),
                      share: slots.share)
    }

    /// "2026-08-17T12:15" -> "12:15". Returns nil rather than a substring if
    /// the shape isn't what's expected, so a changed API format hides the row
    /// instead of printing nonsense.
    private static func clock(from timestamp: String) -> String? {
        let parts = timestamp.split(separator: "T")
        guard parts.count == 2 else { return nil }
        let time = parts[1].prefix(5)
        let fields = time.split(separator: ":")
        guard fields.count == 2,
              let hour = Int(fields[0]), (0...23).contains(hour),
              let minute = Int(fields[1]), (0...59).contains(minute)
        else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    private static func add15Minutes(to clock: String) -> String {
        let fields = clock.split(separator: ":")
        guard fields.count == 2, let h = Int(fields[0]), let m = Int(fields[1]) else { return clock }
        let total = h * 60 + m + 15
        return String(format: "%02d:%02d", (total / 60) % 24, total % 60)
    }
}
