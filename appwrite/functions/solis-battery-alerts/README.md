# solis-battery-alerts

An Appwrite Function that emails a low-battery escalation **while the grid is
down**, and one email when the grid comes back.

| Battery | Email |
|---|---|
| grid lost | `GRID DOWN — battery 88%` (opener, so the restore email has a pair) |
| ≤ 25% | 1 of 5 |
| ≤ 23% | 2 of 5 |
| ≤ 21% | 3 of 5 |
| ≤ 19% | 4 of 5 |
| ≤ 17% | 5 of 5 — `🚨 CRITICAL` |
| grid back | `grid is BACK — battery 40%`, sequence reset |

Each level fires **once per outage**. A drop past several levels in one poll
sends only the most severe of them — three stale emails are worse than one
current one — and latches the rest so they can't fire on the way down.

## Why the gates differ from the macOS app

The app alerts at 24/20/18% gated on **>100 W of draw**, because its job is a
low battery under real load, grid or no grid. That gate exists because the
inverter keeps drawing ~50 W below its cut-off, so SOC drifts past every level
most nights and an ungated alert would cry wolf nightly.

Here the gate is the **outage itself**, which is strictly stronger: with the
grid down, everything the house uses comes out of the battery. No draw gate is
needed, and adding one would suppress a genuine outage on a quiet house.

## Grid state comes from `/alarm/list` and nothing else

Do not be tempted by `data.state` or `alarmCount`. Both were measured across a
healthy dusk and a real outage and neither can tell them apart — `state` read 3
in both, and `alarmCount` read **0 while the NO-Grid alarm was active**. The
only reliable signal is alarm code `1015` / message `NO-Grid` from
`/alarm/list`. See the root `CLAUDE.md`.

## Setup

### 1. Email provider

Appwrite Cloud ships no default email provider for Messaging. In the console:
**Messaging → Providers → Add provider → Email** (Mailgun, Sendgrid, or custom
SMTP). Nothing sends until this exists.

The provider ID is **not** needed anywhere in this function, and is not
recorded here. `createEmail` takes no provider argument — Appwrite routes the
message to whichever email provider is enabled for the project. Keep the ID in
your own notes if you want to manage the provider over the API later; it is
account-specific, so it does not belong in this repository.

### 2. A recipient

Either works; a topic is easier to add a second address to later.

- **Topic:** Messaging → Topics → create → subscribe your email target. Note
  the topic ID.
- **Target:** Auth → Users → your user → **Targets** tab → copy the target ID.
  A user created by hand in the console does get an email target, unverified or not
  — but check the tab rather than assuming, because a send to a user with no
  targets succeeds and delivers to nobody.

### 3. State table

Functions are stateless, so the latches live in one row. **Databases → create a
database → create a table** (`solis-alert-state`) with:

| Column | Type | Required | Default |
|---|---|---|---|
| `firedLevels` | String (64) | no | *(empty)* |
| `outageActive` | Boolean | no | `false` |
| `sessionAlertSent` | Boolean | no | `false` |
| `lastSoc` | Float | no | — |

The function creates the row itself on first run. No permissions needed beyond
the function's own API key.

### 4. The function

**Functions → Create function → Node.js 22**, connect this directory, then set
entrypoint `src/main.js` and build command `npm install`.

Scopes required on the dynamic API key: `messages.write`, `tables.read`,
`documents.read`, `documents.write`.

**Schedule (CRON):** `*/5 * * * *`

Five minutes is deliberate — the upstream reading only changes every ~3 minutes,
so polling faster buys nothing. It costs ~288 requests/day to SolisCloud in the
normal case, because the station reading is only fetched when an outage is
active or just ended; the rest of the time the alarm check is the only call.

### 5. Variables

Mark every `SOLIS_*` one **secret**.

| Variable | Value |
|---|---|
| `SOLIS_STATION_ID` | `defaults read com.faizan.SolisSolarMonitor station-id` |
| `SOLIS_COOKIE` | `defaults read com.faizan.SolisSolarMonitor cookie` |
| `SOLIS_DEVICE_ID` | `defaults read com.faizan.SolisSolarMonitor device-id` |
| `SOLIS_SIGNING_SECRET` | `defaults read com.faizan.SolisSolarMonitor api-signing-secret` |
| `APPWRITE_DATABASE_ID` | from step 3 |
| `APPWRITE_TABLE_ID` | from step 3 |
| `ALERT_TOPIC_IDS` | comma-separated, from step 2 |
| `ALERT_TARGET_IDS` | comma-separated, from step 2 |
| `ALERT_USER_IDS` | comma-separated, optional |
| `NOTIFY_OUTAGE_START` | `false` to drop the grid-down opener |

`SOLIS_SIGNING_SECRET` is SolisCloud's own web-client secret, not ours. It is
**deliberately absent from this repository** for the reason given in
`CLAUDE.md`: publishing it hands out a vendor secret and invites them to rotate
it, breaking this app and every other one built the same way.

## The session expires, and that used to be silent

The cookie captured by the app's WKWebView sign-in does not last forever, and
no server-side flow can renew it. When it dies this function can read nothing
and would go quietly dead — a battery alarm that has stopped working without
telling you.

So an expired session sends **one** `alerts are DOWN` email, latched until the
session works again. Renew by signing in again in the macOS app's Preferences
and copying the new cookie and device-id into the function variables.

## Known limitation: the outage may take out the reporting path

The inverter's data logger reaches SolisCloud over the **house internet**. If
the router is on mains and has no UPS, a grid outage kills the uplink, and
SolisCloud then serves its last reading indefinitely — so the battery level
this function sees freezes at whatever it was when the internet died.

Two consequences:

- **Emails still arrive**, but the SOC in them can be stale. Any reading over
  15 minutes old carries an explicit `⚠️ This reading is N minutes old` line
  with the real level's likely direction. Stale readings are reported, never
  suppressed: going silent exactly when the email matters most is worse.
- **A frozen feed is itself evidence of an outage.** Alerting on "the feed went
  dark" would catch outages this function otherwise misses entirely, and is the
  obvious next thing to build. It is not built — it wasn't part of the ask.

Putting the router and the logger on a small UPS removes the problem at the
source and is worth more than any code here.

## Verification

No test target, same as the rest of the project. The state machine was driven
through 39 scenarios with SolisCloud stubbed at the `fetch` boundary and the
Appwrite SDK stubbed at the module boundary, so the code under test is the
shipped code: the full 26→15% escalation, repeat polls, a fast drop past three
levels, restore-and-reset, a second outage the same night, mid-outage re-arm
(including the 23→25→23 bounce that a margin of 2 would have double-sent),
session expiry latching, transient failures, and stale-reading wording.

The signing was cross-checked against `SolisAPI.computeAuth` by compiling both
and diffing the output over three bodies including a non-ASCII secret —
byte-identical. That, and reproducing a browser-issued signature, are the only
checks `computeAuth` has ever had.
