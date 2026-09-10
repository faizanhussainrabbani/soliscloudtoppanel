# Solis Solar Monitor — macOS

A native SwiftUI `MenuBarExtra` app showing live data from a SolisCloud solar
installation: a menu bar readout plus a dropdown window.

It began as a faithful port of the GNOME Shell extension at
`../solis-solar-monitor@faizan.extension` — same auth flow, same data source,
same polling behaviour, same layout. **It is no longer that.** The data layer
and the auth flow are still the port; the window was redesigned from scratch,
and several features exist here that the original never had. Where the port
still constrains a decision it says so inline; otherwise treat the GNOME
version as history rather than as a spec.

**Most of this was built without version control**, and it cost something: a
backup of the deleted power-flow diagram lived only in a session scratchpad,
the scratchpad was cleaned, and that code is gone for good. The repository
exists now — but the lesson holds for anything kept outside it.

## Credentials and secrets — nothing account-specific is in source

This was not always true. `SolisSettings.register(defaults:)` used to ship a
live session — cookie, authorization header, device-id and station ID — so a
clone of this repository was a working login to one SolisCloud account, and a
screenshot of the Preferences window published it. Preferences also rendered all
of them in full on its first tab; they now sit behind a "Show saved credentials"
toggle, off by default.

Where things live now:

- **Session values** (cookie, authorization, device-id) — UserDefaults, written
  by the WKWebView sign-in. That was always the real source; the hardcoded
  copies were fallbacks the running app never read.
- **Station ID** — UserDefaults, set by hand once. No sign-in flow captures it.
- **`api-signing-secret`** — UserDefaults, set by hand once, and **deliberately
  absent from this repository**. It is SolisCloud's web-client secret, not ours:
  publishing it hands out a vendor secret and invites them to rotate it, which
  would break this app and every other one built the same way. `SolisAPI` takes
  it as a parameter; `keyID` (2424) stays in source because it travels in clear
  text in every request.
- **`content-md5`** — gone entirely. It is an MD5 of each request body,
  recomputed per call, so a stored one could never have been correct.

Setting up a fresh machine:

```sh
defaults write com.faizan.SolisSolarMonitor station-id -string '…'
defaults write com.faizan.SolisSolarMonitor api-signing-secret -string '…'
# then Preferences -> Sign In for the session values
```

With either unset the app shows **"Not configured"** rather than "Session
Expired" — signing in again can never supply a signing secret, and reporting it
as an expired session sends you round the login flow forever.

## Architecture

```
Sources/SolisSolarMonitor/
  SolisApp.swift         @main, MenuBarExtra scene, app delegate (LSUIElement)
  SolisMonitor.swift     state machine + polling; also composes every display string
  SolisAPI.swift         HMAC-SHA1/MD5 request signing + fetch (ported verbatim)
  SolarForecast.swift    Open-Meteo irradiance: peak window + day-vs-week comparison
  SolisSettings.swift    UserDefaults wrapper — gschema keys plus macOS-only additions
  MenuContentView.swift  the dropdown window
  PreferencesView.swift  Setup / Display tabs
  LoginWindow.swift      embedded WKWebView login + credential capture
  Notifier.swift         grid outage/restore + low-battery notifications
  Util.swift             formatting, sun times, station-local day keys, Colors
IconGen/main.swift       generates Resources/AppIcon.icns
build.sh                 builds, ad-hoc signs, optionally installs to /Applications
```

No test target. Verification is done with throwaway proxies — see "How this
project gets verified" at the bottom, which is the most useful section here.

## Build & run

```sh
./build.sh            # -> dist/SolisSolarMonitor.app (ad-hoc signed)
./build.sh --install  # -> /Applications, unregisters the dist/ copy, launches
```

Ad-hoc signing is not optional: `WKWebView` and `UNUserNotificationCenter` both
refuse to run unsigned. `--install` also deletes the `dist/` copy, without
which the app appears twice in Launchpad.

Login-at-startup is handled by System Settings → Login Items, not by code.

## The window

Design direction: **one number leads.** Modelled on Apple's Weather app, where
a single large reading dominates and everything else is subordinate.

```
[warning row — only when something is wrong]
SOLAR OUTPUT                  <- label
0.43 kW                       <- hero, 48pt (32pt when Details is open)
Solar powering the house · about 1 h 20 m of daylight left
[ HOME 0.06 kW ][ BATTERY 96% ][ GRID 0.00 kW ]     <- the other three
Details ⌄
  ... supporting facts, never a value from above ...
Preferences…                                    Quit
```

Rules that hold the design together. Each was arrived at by breaking it first:

- **Nothing appears twice.** The hero, the tiles and the Details rows are
  disjoint. Details carries what the summary can't: today's totals, the grid
  cost, battery flow, sun times. When a fact is promoted to the summary it must
  be *removed* from Details, not copied — that regression has happened twice.
- **Colour means "this is live", not "this is the battery one".** Every icon
  dims to `Color.solisDim` when its own metric is at zero. Category colour on
  labels was removed: the words already say which metric it is. The two
  exceptions are semantic — red when the battery is low, amber when data is
  stale.
- **Each dim flag is about its own row's value.** `solarAsleep` (output now) and
  `solarTodayZero` (today's total) are different questions; driving the daily
  total's icon from the instantaneous reading meant "12 kWh" sat in grey all
  evening.
- **Silence when healthy.** The top row is empty unless something needs
  attention. It has shrunk three times — station title, then full timestamp,
  then the always-green dot, then the station name — because none of them told
  the reader anything. Anything in that position now means a problem.
- **The hero has two fixed sizes, never `minimumScaleFactor`.** See the bug
  list below.
- **The window and the menu bar cannot disagree.** Both take the hero/slot
  choice from the same `adaptiveShowingLoad` flag, and shared formatting from
  `powerText`. Independent tests would eventually diverge; they have before.

Details is grouped by **time horizon**, not by subsystem — it used to be
solar / grid / battery, which is where the data comes from rather than what the
reader is asking, and it mixed tenses inside every group (Sunset sat among
today's totals; "Battery Idle" sat beside a projection):

- **TODAY** — Solar, Used, Bought from grid, Cost, and either Sunshine
  (daytime, forecast) or Vs average (after dark, actual)
- **AHEAD** — Peak window (today's, or tomorrow's once the sun is down),
  Sunset/Sunrise, On battery until / Full at
- **EQUIPMENT** — Battery flow, Full charge (when the pack last topped out),
  Inverter temperature, and an alarm row when one is active

Then the reading's own timestamp, ungrouped and last, because it is metadata
about the panel rather than a fact about the system.

Adding "Used" was what surfaced a gap the old grouping had hidden for weeks:
total consumption, the most basic figure in a home energy app, was missing
entirely.

**Removed, and not by accident:** the four-row metric list (`MetricRow`), the
Advanced Information dashboard (battery voltage, throughput, inverter max, sun
hours, CO₂/trees/coal), and the 6-edge power-flow diagram. The diagram was a
significant piece of work — `industryCurrentFlowMapV2`, threshold-gated edges,
hand-verified node geometry — and it is gone with no backup. Rebuilding is a
rewrite. Don't assume it can be restored.

## The menu bar label is a rendered image

`SolisMonitor.renderPanelImage` lays the panel out as an ordinary SwiftUI
`HStack` and renders it to a template `NSImage` via `ImageRenderer`.

**Do not try to hand `MenuBarExtra` a view hierarchy again.** Two attempts,
both verified failures:

1. `HStack` + `ForEach` over icon/text segments — only the first segment drew;
   the battery vanished from the menu bar.
2. A single `Text` with `Image(systemName:)` interpolated in — the text drew,
   every image was silently dropped.

Apple's position on styling this label is that you can't, because the OS owns
it ([forum thread 726565](https://developer.apple.com/forums/thread/726565)).
An *Image* label is supported, hence the render. Two details that took a
correction each:

- **Constrain the height before rendering (`.frame(height: 18)`), never scale
  the finished bitmap.** Rendering at natural size and shrinking 21pt → 17pt
  also shrank the type to ~10.5pt, visibly smaller than every neighbouring
  menu bar item.
- **`isTemplate = true`** is what makes it invert on light and dark menu bars.
  It keeps only alpha, so this label is monochrome by construction — the
  battery's low-charge red cannot appear here.

`panelText` still exists as a plain string for the log and `panel-debug-tick`.

## Icons

SF Symbols in the window and the rendered menu bar label. **A misspelled symbol
name renders as nothing, silently, with no build error** — check new names with
`NSImage(systemSymbolName:accessibilityDescription:) != nil` before shipping.

- Solar `sun.max.fill` · Home `house` · Grid `powerplug.fill`
- Battery steps with charge (`battery.25percent` … `battery.100percent`), with
  a separate small `bolt.fill` accessory while charging. SF Symbols only has
  `battery.100percent.bolt` — no level-specific bolt variants — so folding
  charging into the level symbol drew a *full* battery beside the text "54%".
- Home is `house`, not `bolt.fill`, so the bolt means charging and only
  charging. The outline weight was chosen over `house.fill` deliberately.
- Grid is **teal**, not Adwaita purple: purple carried no meaning, it was
  inherited identity.

## Features the GNOME original doesn't have

### Adaptive panel mode

`panel-display-mode = "adaptive"`. The menu bar fits two metrics; in the ported
modes one is always solar, which reads `0.00 kW` for half of every day.

- **Slot 1** — solar, or home load once solar goes quiet.
- **Slot 2** — battery %, or grid once the battery is low *and* isn't the thing
  supplying the house. Not a plain `SOC <= 25 → grid`: a low battery that's
  still discharging is the most important number on screen.

**Both swaps are hysteretic and that is the feature, not polish.** The dead
bands are the primary anti-flap: solar yields at `<= 0.01 kW` but reclaims only
above `0.05`; battery yields at `<= 25%` but reclaims at `>= 30%`. Readings
inside a gap hold the current slot. The first sample after launch is adopted
outright (`adaptiveSeeded`). **Don't collapse any of these into direct
comparisons.**

On top of the dead bands a swap must hold for `confirmWindow = 120` seconds,
**converted to a poll count against the live `refresh-interval` and floored at
1** — never a flat poll count. See the bug list.

### Low-battery notifications

`checkBatteryAlerts`: three alerts at **24 / 20 / 18%**, each firing only while
the battery is drawn from at more than **100 W**.

**That gate is deliberate and load-bearing** — the user's reasoning, not a
guess. The Solis inverter keeps draining below its configured cut-off at ~50 W
of standby draw, so SOC does drift past all three levels every night. The gate
suppresses those harmless crossings and fires only when real load lands on a
low battery, i.e. a grid outage. Lowering it would produce a nightly false
alarm and train the user to ignore it. Verified against a full
cutoff → drift → outage sequence.

Once per crossing, not once per poll (`firedBatteryAlerts` latches; a level
re-arms at +2 points). A fast drop fires only the most severe level crossed.

Confirmed delivering via **`UNUserNotificationCenter`**, authorization granted,
no osascript fallback. `Notifier.notify` logs which path it took, because a
denied authorization downgrades silently. The macOS notification database is
not readable here (needs Full Disk Access) — the log line is the only evidence.

### Battery time remaining

`batteryRuntimeHours` → "about 1 h 55 m left" in the caption, and "On battery
until 01:17" in Details. Same estimate, two framings, deliberately not the same
string twice.

SolisCloud does **not** report battery capacity (`batteryCapacityEnergy` is 0;
`capacity` = 6.45 is the PV array in kWp), so capacity and cut-off are
preferences. With capacity unset the row prompts; when the battery is simply
idle the row is hidden — those used to be conflated, so a correctly configured
app showed what looked like an error whenever the battery rested.

Not "empty by": with a cut-off set, that moment is when the inverter stops
supporting the house, not when the battery is flat.

### Full charge tracking

`recordFullCharge` keeps two high-water marks per station-local day —
`settings.socDayPeaks` and `settings.voltageDayPeaks` — and the EQUIPMENT row
"Full charge" reports when the pack last genuinely topped out: "3 days ago ·
81% today", "3 days ago · 100% by count only", or "None in 21 recorded days".

**Two marks, and that is the whole point.** SOC drifts, so it can creep to 100%
while the pack sits at the float setpoint and the cells never rise far enough to
balance. Peak *voltage* is the physical evidence. Observed live: SOC 97% with
the pack at 53.52 V, i.e. exactly `batteryFcvSet`, 2.6 V under absorption.

**Voltage leads; SOC corroborates.** A day counts as a real top-out if peak
voltage cleared `FullCharge.absorptionThreshold` — the midpoint between
`batteryFcvSet` and `batteryAcvSet` — *and* peak SOC reached
`nearFullSOC` (95). With no usable voltage evidence it falls back to SOC alone
and demands a full `fullSOC` (100).

That split is a correction, and the reason matters. It was originally
`SOC >= 100 AND voltage >= threshold`, which was right while SOC came from the
BMS and was coulomb-counted. Once support switched the inverter to "Without
COMM" (see below) SOC became a voltage inference with a few points of error —
it read a spurious 100 during a BMS re-init on 2 Sep, and 99 on 6 Sep on a day
the pack demonstrably reached 55.0 V. The old rule let that soft estimate veto
hard voltage evidence, and the row claimed "2 days ago" the morning after a real
absorption charge.

**SOC is still checked, and not vestigially.** It guards the one case voltage
alone gets wrong: terminal voltage lifted over the threshold by a heavy charge
current part-way up the pack. That is tens of SOC points short of full, not
five, so 95 rejects it while absorbing the observed drift.

The midpoint, not "within X of absorption": it is self-scaling, and float
actively holds the pack at `fcv`, so a pack cannot drift halfway to absorption
by accident. Clearing it means the inverter deliberately pushed it there.

Voltage comes from `storageBatteryVoltage` in station/detailMix — **no extra
request**, sampled every poll. That is the *inverter's* meter, not the BMS's
`batteryVoltage`, deliberately: it is compared against the inverter's own
setpoints and the two meters read ~0.2 V apart, so both sides of the comparison
share a reference frame.

**Three exemptions, all the same principle — never claim what the evidence
can't support:**

- Setpoints unknown (they arrive on the throttled /inverter/detail fetch) →
  judge on SOC alone.
- A day with no voltage record at all → not demoted. Absence of evidence is not
  evidence the charge was incomplete.
- **The earliest day in the voltage record is exempt**, derived from
  `voltagePeaks.keys.min()`. Recording starts mid-day, so that day's mark covers
  only the hours after the app first ran; a pack that absorbed at 11:00 and was
  back at float by 16:00 would be demoted on evidence that was never collected,
  making the feature's first impression a false alarm.

The row says "by count only" rather than printing the voltage, because "53.6 V"
only informs a reader who already knows the 56.1 V setpoint. State the
conclusion, not the raw evidence.

**The row is hidden on a day the pack did reach 100%**, because "Full charge:
Today" asks nothing of the reader, and a row that says the same thing every day
stops being read — so it would be invisible on the day it finally said "9 days
ago". Same principle as the status line. It is deliberately *not* hidden for
the whole `recentDays` window: a gap is worth seeing while it is still small,
and suppressing it for a week means it reappears at day eight with no sense of
whether it is drifting or was fine yesterday. **The recording continues
regardless of what is displayed** — hiding the row must never stop the history.

Why it exists: LiFePO4 balances its cells and re-anchors the BMS's SOC estimate
at the top of charge. This system rides through roughly **five grid outages a
day** (1547 NO-Grid records in the alarm history), so reaching 100% is not
something that can be assumed — and neither the app nor SolisCloud's own site
would have said so.

- **The threshold is 100, not `Curtailment.fullSOC`'s 98, and that is
  deliberate.** Curtailment asks "is the pack full enough that the inverter is
  throttling the array", where 98 is close enough. This asks "did the pack
  actually reach the top of charge", and a charge that stops at 98 is precisely
  the one that didn't. Two constants, two questions — don't unify them.
- **Days are keyed to the station's timezone**, from `dataTimestamp` plus the
  response's `timeZone`. Verified that `dataTimestamp` is a true UTC epoch
  (1788251642539 renders as 13:34:02 UTC+05:00 *and* 08:34:02 UTC), unlike some
  fields in this API which arrive pre-shifted.
- **"No full charge" and "not enough history" are different rows.** Below
  `minimumRecordDays = 14` it reports the record's length instead of making a
  claim about the battery. There is nothing to backfill from — `/station/day`,
  `/inverter/day`, `/battery/pile/chart` and six siblings all 404 — so a fresh
  install genuinely cannot distinguish the two, and stating the first on the
  evidence for the second is the assume-one-cause bug from the list below.
- **Record length counts observed days, not the span since the first entry.** A
  fortnight with the Mac switched off is not a fortnight of evidence.
- Only recorded when `batteryPercent` was actually present; the `?? 0` fallback
  would otherwise write a 0 peak and manufacture a record day with no battery
  data in it.
- No new colour meaning: the icon follows the existing dim rule (lit when a
  full charge is within `recentDays = 7`), rather than adding a third semantic
  amber alongside low-battery red and stale-data amber. The lit state is still
  reachable — days 1 to 7 show the row *and* light it.

Verified with a 24-scenario proxy (`recordFullCharge` copied verbatim, the two
settings stores swapped for injected dictionaries), 6 pruning cases, and a
14-case suite for the voltage-leads rule that replays the real 01–07 Sep
history out of `defaults`.
**Delete the proxy binary before rebuilding it** — a compile failure otherwise
runs the previous binary and prints a full page of passes for code that never
compiled. That happened once during this work.

**What the BMS cannot tell you, and why no setting will fix it:** the Pylontech
LV CAN protocol carries pack-level values only — 0x351 limits, 0x355 SOC/SOH,
0x356 voltage/current/temperature, 0x359 alarm bitfields. **Per-cell voltages
and per-module temperatures are not in the spec at all**, which is why
`bmsMinU`/`bmsMaxU` read 0 and `bmsMinTemp`/`bmsMaxTemp` read -273. Those
SolisCloud fields exist for other battery protocols. Don't chase them through
inverter settings or firmware.

`batteryFailureInformation01`/`02` and `batteryAlarm` looked like the 0x359
bytes, whose bit map is published (byte 1 bit 4 = cell imbalance, bit 3 = BMS
internal error), and were briefly written up here as "worth logging". **They are
dead.** Measured during an active Batt_Comm_FAIL on 2 Sep, all three still read
`"0"`. Now observed in both conditions, they are the `alarmCount` trap exactly.
Don't build on them.

**What does work, measured in both conditions on 2 Sep:** `bmsState` flips
0 → 1 and `bmsBmsState` 3 → 0 when the link drops. `batteryChargingCurrent`
goes 50 → 0, so it is not the static nameplate it looked like while healthy.
None is used for detection — `BatteryLink` infers it from station/detailMix
instead, because all of these live behind the /inverter/detail throttle.

### A silent BMS is not a flat battery

When the inverter loses its comms link to the pack, **every BMS-sourced field in
the API collapses to zero at once** while the inverter's own DC meter keeps
reading. Captured live during an active Batt_Comm_FAIL, 2 Sep 09:10:

| | healthy (1 Sep) | during the fault |
|---|---|---|
| `batteryPercent` / `batteryCapacitySoc` | 60 | **0** |
| `batteryVoltage` (BMS) | 53.16 | **0** |
| `bstteryCurrent` | 7.7 | **0** |
| `batteryHealthSoh` | 96 | **0** |
| `batteryChargingCurrent` | 50 | **0** |
| `batteryDischargeLimiting` | 100 | **0** |
| `bmsBmsState` | 3 | **0** |
| `bmsState` | 0 | **1** |
| **`storageBatteryVoltage`** (inverter's own meter) | 53.4 | **52.8** |
| `batteryUvpSet` / `batteryFcvSet` (inverter settings) | 42.0 / 53.5 | 42.0 / 53.5 |

Before this was handled the app rendered a dead sensor as a flat battery: 0%,
red, flagged critically low, with a runtime estimate to match — on a pack
sitting at 52.8 V.

`BatteryLink.isSilent` separates the two. **SOC 0 is the tell**: the inverter
stops discharging at `socDischargeSet` (15% here), so a genuine zero is not
reachable in normal operation. `storageBatteryVoltage` corroborates, and
`batteryUvpSet` is the reference because it is the *inverter's* own setting and
was verified to survive the fault intact while the BMS fields around it went to
zero.

**Inferred from station/detailMix on purpose.** The alarm list names this fault
explicitly and `bmsState` marks it too, but both sit behind the /alarm/list and
/inverter/detail throttle — up to 8 minutes at a 240 s interval, all of it
showing a false 0%. detailMix is fetched every poll and costs nothing extra.

The only surviving path to a displayed 0% is a pack that is present and
genuinely collapsed below the cut-off. Every degraded input — no voltage field,
zero voltage (a NO-Battery condition, reasoned rather than measured), setpoints
not yet fetched — resolves to "unreadable" rather than to a charge state.

What changes while silent: the tile and menu bar read `—`, the symbol becomes
`antenna.radiowaves.left.and.right.slash` (not `battery.0percent`, which still
asserts a charge level; `battery.slash` does not exist), `batteryLow` stays
false so the fault never spends the low-battery red, the runtime estimate is
suppressed, `checkBatteryAlerts` is skipped outright, and the full-charge
tracker records nothing.

**The adaptive slot machine holds rather than swaps.** A silent BMS reports 0%
*and* 0 kW, which reads as "low and not discharging" — exactly the condition
that hands slot 2 to grid. The dead bands cannot help, because the placeholder
sits far outside them. Verified with a 20-case proxy including the measured
healthy and fault samples.

### Sun times and daylight

`Util.sunTimes` — NOAA approximation from the station's `latitude`/`longitude`
(present in the API response). Verified against published times for London and
Sydney, and hand-checked for Karachi. Returns nil inside a polar day.

In daylight the caption carries daylight-remaining; after dark it carries the
battery estimate. The battery's runtime is the wrong question at noon and the
sun's is the wrong question at midnight.

### Forecast: peak window and day quality (`SolarForecast.swift`)

One Open-Meteo request (free, no key; sends only lat/lon) yields both:

- **Peak window** — the best contiguous **3 hours** for production today, from
  15-minute irradiance. Fixed duration on purpose: "the span above 85% of
  today's peak" was tried and returns *six hours* on a flat day, because 85% of
  a low peak is a wide band.
  Three states, recomputed every poll from the clock: upcoming
  (`12:00 – 15:00`), underway (`Now, until 15:00`, icon lit), and over (row
  hidden). Stored as absolute `Date`s in the station's timezone, so a Mac in
  another zone still tracks the panels.
- **Today's sun** — today's forecast total against the mean of the previous 7
  days. **Weather against weather, deliberately.** Actual output against
  modelled output is not trustworthy on this system: it runs curtailed for much
  of every sunny day, so a modelled expectation reads ~50% low daily and would
  report a permanent fault. ±5% counts as no difference.

`past_days=7` applies to the 15-minute series too, so it must be filtered to
today before the sliding window runs — otherwise the "best three hours" can
land on last Tuesday.

Refetched at most every 3 hours, and always after the date changes. Timestamp
is set *before* the request, so a failure waits rather than retrying every poll.

### Curtailment

`heroCaption` checks this first: with the battery full (`>= 98%` and not
charging) and no export, the inverter throttles the array to whatever the house
draws. Conservation then forces solar == load, which is why the hero and the
Home tile showed the same number — that identical pair is what led here.

The caption claims only that output is **capped**. Quantifying the loss needs
modelled clear-sky output and its derate guesses; the cap is a fact, the loss
would be an estimate dressed as one.

### Stale-data detection

`dataTimestamp` (inverter's report time) against `nowZoneTime` (SolisCloud's
clock), both epoch millis, both server-side so a skewed Mac clock can't fake an
outage. Normal lag is ~3 minutes; over **15 minutes** shows an amber "No update
for 25 min" row and a ⚠️ in the menu bar.

This exists because a successful fetch was being treated as fresh data. A
logger knocked offline by a home internet outage leaves SolisCloud serving its
last reading indefinitely, and every number looked live while hours old.

## Bugs this codebase has already had — don't reintroduce

- **Any tuning constant expressed in polls.** `confirmPolls = 2` with a comment
  claiming "~2 min at the default 60 s" cost 2 × 240 s = **8 minutes** at the
  user's real interval, and read as a frozen panel. Check
  `defaults read com.faizan.SolisSolarMonitor` before reasoning about timing.
- **`minimumScaleFactor` on anything.** It let SwiftUI shrink the hero a third
  whenever the window grew tall, unpredictably. The hero now has two explicit
  sizes and `.fixedSize()`. It was also live in `StatTile` and `MetricRow` for
  a while afterwards.
- **A value promoted to the summary but left in Details.** Happened with all
  four metrics, then again with time-remaining the same day.
- **An icon contradicting the number beside it.** A full-strength sun at
  0.00 kW; a full battery glyph beside "54%".
- **`NSLog(someString)`.** `panelText` contains a literal `%`, and NSLog treats
  argument one as a format string — it printed `🔋 87` and read garbage off the
  stack. Always `NSLog("%@", s)`.
- **Assuming API units are consistent.** `monthEnergy` is kWh while
  `yearEnergy` is MWh. The day comparison refuses to compute unless the unit
  strings match.
- **Rendering a placeholder as a reading.** A silent BMS returns 0 for every
  battery field, and the app showed 0%, in red, flagged critically low, with a
  runtime estimate — on a pack at 52.8 V. The general form: a field that is 0
  because nothing measured it looks exactly like a field that is 0 because the
  thing it measures is 0. Ask what the *other* instruments say before believing
  a zero. See `BatteryLink`.
- **A fallback message that assumes one cause.** "Set capacity in Preferences"
  appeared whenever there was no estimate, including when the battery was
  merely idle on a fully configured app.

## `data.state` is not grid health — settled, and replaced

For a long time the Grid "fault" row and the outage/restore notifications were
gated on `state == 1`, inherited from the GNOME original. That is gone. The
field was measured across both conditions and cannot tell them apart:

| | healthy dusk | real grid outage |
|---|---|---|
| `state` | 3 | 3 |
| `alarmCount` | 0 | **0** |
| `uAc1` / `fac` | — | 0 V / 0 Hz |
| `/alarm/list` | empty | code 1015 "NO-Grid" |

Two things to take from that table. `state` reads 3 whether the grid is fine or
absent, so a "fault" inferred from it fired every evening at dusk and stayed
silent through an actual outage. And **`alarmCount` reads 0 while an alarm is
active** — it was the obvious replacement and it would have been silently dead
forever.

Grid health now comes from `/alarm/list` (see below). **Don't gate anything on
`data.state`, and don't trust `alarmCount`.**

`uAc1` and `fac` are the honest physical signal — 0 V and 0 Hz during the
outage, 237 V and 49.93 Hz once it returned — and `currentState` mirrored the
alarm code (1015) while it was down, but reads 3 when healthy, i.e. it is the
same unreliable value as `state`. The voltage pair is logged every poll so the
baseline is recorded; wiring detection to it is a small change now that both
conditions have been observed.

## Device endpoints

Three endpoints beyond `station/detailMix`, all signed by the same scheme with
a different `path` — verified by reproducing a browser-issued signature byte
for byte, which is also the only check `computeAuth` has ever had:

- **`/alarm/list`** — the only trustworthy source of grid state. Returns
  `alarmCode`, `alarmMsg` ("NO-Grid"), and a begin time. Polled on a throttle:
  every third station read while clear, every read once something is active, so
  a clearing outage is noticed promptly without paying for it all day.
- **`/inverter/detail`** — 809 fields. Used for `socDischargeSet`,
  `batteryHealthSoh`, `inverterTemperature`, and the grid-voltage candidates.
  Fetched on the same throttle, not per poll.
- **`/battery/pile/detail`** — charge/discharge current limits and BMS state.
  Nothing from it is displayed; the temperatures it reports are unavailable on
  this pack (`bmsTemp` 0, `bmsMinTemp` -273).

Discharge floor: three fields disagree — `socDischargeSet` 15, `epsDDepth` 20,
`offGridDDepth` 30, against an observed ~25. The code picks by which error is
survivable: the reported on-grid value when on grid, the most conservative of
the three when off grid, since overstating runtime only has consequences during
an outage.

## API load

~368 requests/day: **360 to SolisCloud** (one per 240 s poll) and **8 to
Open-Meteo** (3-hourly, occasionally 9 at a date rollover). Open-Meteo's free
tier allows 10,000/day. Forecast calls only follow a successful SolisCloud
read.

Polling faster than ~2–4 min gains nothing: the upstream reading only changes
every few minutes. At a 10 s interval, **15 of 16 polls returned a
byte-identical panel string.**

## How this project gets verified

There's no test target and no screen recording, so verification is done by
building throwaway proxies. This has caught real defects repeatedly and is the
practice most worth continuing.

- **Replicate the logic verbatim in a scratchpad Swift file and drive scenarios
  through it.** Used for the adaptive slot machine (12 scenarios), the battery
  alerts (9, plus the cutoff/drift/outage sequence), the runtime estimate (12),
  the peak window's three states (8 times of day), the day comparison, and
  staleness (10). Copy the code — don't reimplement it, or the test proves
  nothing.
- **Render UI to a PNG with `ImageRenderer` and look at it.** This is how the
  menu bar label was sized, how the charging bolt was checked for crowding, and
  how the house-glyph options were compared. It caught the type being too
  small, the inconsistent heights, and a symbol name that silently drew nothing.
- **Verify API claims against a live response before building on them.** Every
  field used here was confirmed by a temporary dump in `updateUI` gated on
  `SOLIS_DUMP_FIELDS`. Wrong guesses this caught: the belief that
  `pvToLoad`/`pvToGrid` didn't exist, the `sscCurrentFlowMap` reliability gap,
  `state = 3`, absent battery capacity, and the presence of `azimuth = 180`.
- **Diagnostics require running the binary directly** — `NSLog` output from
  this app is *not* retrievable via `log show`, even with `--info --debug` and a
  matching process predicate. It does reach stderr:

  ```sh
  pkill -x SolisSolarMonitor
  /Applications/SolisSolarMonitor.app/Contents/MacOS/SolisSolarMonitor 2>&1 | tee ~/solis.log
  ```

  Run the installed bundle, not `swift run` — the ad-hoc signature matters.
  Note `log` is a zsh builtin; use `/usr/bin/log`.
- **`panel-debug-tick`** appends an incrementing counter to the panel text:
  `defaults write com.faizan.SolisSolarMonitor panel-debug-tick -bool true`.
  It exists because watching the numbers is not a valid test of whether the
  label re-renders — the upstream data barely changes. **Settled: the
  `MenuBarExtra` label does re-render from `@Published` changes.** Don't
  re-investigate.
- **`osascript`/System Events has no accessibility permission here** (-1719),
  so the menu bar text cannot be read programmatically and full UI automation
  isn't available. Retain-cycle fixes get verified by tracing the reference
  graph by hand.

## Working notes

- **Every deviation is deliberate and documented inline with the reasoning**,
  usually naming the specific bug that motivated it.
- **Design directions go through options with trade-offs stated, not silent
  picks** — the three redesign directions, the house-glyph comparison, and the
  hero-resize question were all presented as choices first. Renders help.
- **Scope stays matched to the ask.** Adjacent problems found during a task get
  reported, not silently fixed.
- **The user's design judgement has been right more often than mine**, and
  several of these features exist because they pushed back: the dimming rule,
  dropping direction arrows, removing the station name, sunset over battery
  time in daylight, the peak window, keeping the 100 W alert gate, and
  rejecting "empty by". When a suggestion here gets challenged, re-examine it
  rather than defending it.
