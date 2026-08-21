# Solis Solar Monitor for macOS

A menu bar app for a SolisCloud-connected solar installation. It shows two live
readings in the menu bar and opens a window that tries to answer questions
rather than list numbers.

```
☀ 2.40 kW | 🔋 78%          ← menu bar

SOLAR OUTPUT
2.40 kW
Solar powering the house and charging the battery · about 4 h 20 m of daylight left

[ HOME 0.80 kW ]  [ BATTERY 78% ]  [ GRID 0.00 kW ]

Details ⌄
  TODAY       Solar 9.00 kWh · Used 9.29 kWh · Bought from grid 1.29 kWh
              Cost 24.51 PKR · Sunshine 10% above last week
  AHEAD       Peak window 12:00 – 15:00 · Sunset 19:03
  EQUIPMENT   Battery Charging 1.50 kW · Inverter 41 °C
```

Built for one household's system, so some choices are specific to it — a hybrid
inverter with battery storage and no export/net metering. Most of it generalises;
the parts that don't are called out below.

## What it does

**Adapts to the time of day.** The menu bar fits two readings. Showing solar
output for 24 hours means half the day reads `0.00 kW`, so the first slot
switches to house load once solar goes quiet, and the second switches from
battery to grid when the battery is low *and* isn't the thing supplying the
house. Both swaps are hysteretic, so a reading hovering at a threshold doesn't
flicker between them.

**Answers rather than reports.** The window's caption is a sentence — "Running
on battery · about 1 h 55 m left", "Battery full — solar capped at house load" —
composed from the readings rather than listing them.

**Tells you when power is free.** With the battery full and no export path, the
inverter throttles the array to whatever the house is drawing. The app detects
that state and says so, because anything you switch on during it uses generation
that would otherwise be discarded.

**Forecasts the best hours.** One request to [Open-Meteo](https://open-meteo.com)
(free, no key) gives 15-minute irradiance for today, from which it picks the best
contiguous three hours — so the window moves with the weather instead of being
the same clock times every day. After sunset it points at tomorrow's.

**Estimates battery runtime honestly.** Time remaining accounts for the pack's
reported state of health and the discharge floor the inverter is actually
configured with. When any input is missing, the estimate is hidden rather than
guessed.

**Warns about stale data, not just failed requests.** A successful API call
doesn't mean fresh data: a logger knocked offline by an internet outage leaves
the cloud serving its last reading indefinitely. The app compares the reading's
own timestamp against the server's clock and says "No update for 25 min".

**Notifies on grid loss and low battery.** Grid state comes from the inverter's
alarm list, which names the fault explicitly. Low-battery alerts fire at 24 / 20
/ 18%, but only while the battery is under real load — a battery drifting down
overnight on standby draw is not an emergency and shouldn't wake anyone.

## Requirements

- macOS 14 or later (Apple silicon or Intel)
- Swift toolchain — Xcode Command Line Tools is enough, no Xcode project needed
- A SolisCloud account with a station

## Build

```sh
./build.sh            # → dist/SolisSolarMonitor.app
./build.sh --install  # → /Applications, then launches it
```

Ad-hoc code signing is applied automatically and isn't optional: `WKWebView` and
`UNUserNotificationCenter` both refuse to run from an unsigned bundle.

The app runs as an accessory — menu bar only, no Dock icon. To start it at login,
add it in **System Settings → General → Login Items**.

## Configuration

**No credentials are included in this repository**, deliberately. Two values must
be set once per machine:

```sh
defaults write com.faizan.SolisSolarMonitor api-signing-secret -string '<secret>'
```

The request-signing secret belongs to SolisCloud's web client, not to this
project, so it isn't distributed here. Without it the app reports **"Not
configured"** rather than pretending to be signed out.

Everything else comes from signing in: open **Preferences → Sign In**, log in
through the embedded browser and navigate to your station page. The session
cookie, authorization header, device ID and station ID are captured
automatically and stored in UserDefaults.

Optional, in **Preferences → Display**:

| Setting | Purpose |
|---|---|
| Refresh interval | Default 60 s. Longer is usually better — see below |
| Panel format | Adaptive, Compact, Full or Minimal |
| Battery capacity | Nameplate kWh. Required for runtime estimates; the API doesn't report it |

## How it works

**The menu bar label is a rendered image.** `MenuBarExtra` won't draw `Image`
views in its label — not inside a container, and not interpolated into a `Text`.
Both were tried and both silently dropped the images. So the label is laid out as
an ordinary SwiftUI view offscreen and rendered to a template `NSImage` via
`ImageRenderer`. Template rendering keeps only alpha, which is what makes it
invert correctly on light and dark menu bars — and why the label is monochrome by
construction.

**Data comes from SolisCloud's web API**, the same endpoints its own site uses,
signed with HMAC-SHA1 over the request body and path. Four are used: station
detail, alarm list, inverter detail and battery detail.

**Roughly 480 requests a day** — one station read per poll, plus alarm and
inverter detail on a throttle, plus ~8 to Open-Meteo. Polling faster than a few
minutes gains nothing: the upstream reading only changes every few minutes, and
at a 10-second interval 15 of 16 polls returned a byte-identical result.

## Continuous integration

Two workflows run on push and pull request:

- **CI** — builds release with `-warnings-as-errors`, assembles and ad-hoc signs
  the app bundle, verifies the signature, and runs a credential guard over every
  tracked file. SwiftLint also runs but is advisory for now.
- **CodeQL** — Swift security analysis, plus a weekly scheduled run so new query
  packs get applied to code that hasn't changed.

The credential guard (`scripts/check-secrets.sh`) is specific to this project
rather than a generic scanner, because the thing that nearly leaked — a 32-char
hex signing secret and a session cookie — matches no known provider pattern.
Every check is verified in both directions: it passes on a clean tree, and each
pattern was confirmed to actually fire against a planted fake.

## Known limitations

**This uses an undocumented API.** It reads a browser session rather than an
official API key, so a change on SolisCloud's side can break it without notice.
Sessions also expire; when that happens the app says so and you sign in again.

**Battery capacity isn't reported.** `batteryCapacityEnergy` returns 0 and
`capacity` is the PV array in kWp, so capacity is a setting. State of health
*is* reported and is applied to it.

**`data.state` is not grid health.** It reads the same value during a healthy
evening and a real outage, and `alarmCount` reads 0 while an alarm is active.
Neither is used. Grid state comes from the alarm list.

**The discharge floor is ambiguous.** Three fields disagree —
`socDischargeSet`, `epsDDepth`, `offGridDDepth`. The code uses the reported
on-grid value while on grid and the most conservative of the three when off
grid, on the grounds that overstating runtime only has consequences during an
outage.

**No tests.** Verification was done by replicating logic in throwaway harnesses
and by rendering UI to PNGs and looking at them. That caught real defects
repeatedly, but it isn't a suite you can run.

## Credits

A port of, and departure from, a GNOME Shell extension of the same purpose. The
data layer and authentication flow follow the original; the window was
redesigned from scratch.

Not affiliated with, endorsed by, or supported by Ginlong Solis or SolisCloud.
