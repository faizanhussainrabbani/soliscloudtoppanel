// Emails a low-battery escalation while the grid is down, and one email when
// the grid comes back.
//
//   grid out and SOC <= 25 -> email 1 of 5
//                     <= 23 -> email 2 of 5
//                     <= 21 -> email 3 of 5
//                     <= 19 -> email 4 of 5
//                     <= 17 -> email 5 of 5, most critical
//   grid restored          -> "grid is back" email
//
// This is a cloud counterpart to the macOS app's local notifications, not a
// copy of them. The app alerts at 24/20/18% gated on >100 W of draw, because
// its job is to catch a low battery under real load whether or not the grid is
// up. Here the gate is the outage itself, so the draw gate is not needed: if
// the grid is down, everything the house uses is coming out of the battery.

import { Client, Messaging, TablesDB, ID } from 'node-appwrite';
import { fetchStation, fetchAlarms, isGridLoss, OK, SESSION_EXPIRED } from './solis.js';

/** SOC levels, most severe last. Each fires once per outage. */
const LEVELS = [25, 23, 21, 19, 17];

/**
 * How far the battery must recover before a level can fire again *within the
 * same outage* (solar charging it back up mid-outage, say).
 *
 * 4, not the app's 2, because the levels here are only 2 points apart. A
 * margin of 2 would re-arm level 23 the moment SOC touched 25, so a reading
 * flickering between 24 and 25 could send the same email repeatedly. 4 is two
 * full steps and cannot ping-pong.
 *
 * A grid restore resets every level regardless, so a second outage the same
 * night starts the sequence again from 1 of 5.
 */
const REARM_MARGIN = 4;

/**
 * A reading older than this is reported as such in the email body rather than
 * suppressed.
 *
 * Suppressing would be the wrong call: during an outage the house internet may
 * be down, which freezes what SolisCloud serves. Going silent exactly when the
 * user most needs the email is worse than sending one that says how old the
 * number is.
 */
const STALE_SECONDS = 15 * 60;

const ROW_ID = 'state';

/**
 * Logged on every run, and bumped by hand whenever this file changes.
 *
 * It exists because "is the deployment I'm looking at the code I just wrote?"
 * was answered by comparing deployment IDs, which proves only that *something*
 * was uploaded. A forced-outage test then read as a logic failure when the
 * running build simply predated the feature. The log line is the only thing
 * that can settle it, so it prints unconditionally and first.
 */
const BUILD = '3-force-switch';

/**
 * Test switch: set DRY_RUN_FORCE_OUTAGE to a battery percentage to make this
 * run behave as though the grid were down at that level — e.g. `21` to produce
 * the "3 of 5" email on demand.
 *
 * It exists because the alternative is waiting for a real outage to find out
 * whether the email path works, and an untested alarm is not an alarm. It
 * overrides only the two inputs the decision rests on, so everything
 * downstream — the latching, the escalation, the wording — is the real code.
 *
 * It writes real state. After removing the variable, the next run sees the grid
 * up with an outage recorded and sends a genuine "grid is BACK" email, then
 * resets. That is correct behaviour, not a leak: it also proves the restore
 * path. Expect that email.
 */
const forcedSOC = Number.parseFloat(process.env.DRY_RUN_FORCE_OUTAGE ?? '');
const FORCING = Number.isFinite(forcedSOC);

export default async ({ req, res, log, error }) => {
  log(`solis-battery-alerts build ${BUILD}` +
      `, force=${process.env.DRY_RUN_FORCE_OUTAGE ?? 'off'}`);
  const env = requireEnv(['SOLIS_STATION_ID', 'SOLIS_COOKIE', 'SOLIS_DEVICE_ID',
                          'SOLIS_SIGNING_SECRET', 'APPWRITE_DATABASE_ID', 'APPWRITE_TABLE_ID']);
  if (env.missing.length) {
    error(`Missing environment variables: ${env.missing.join(', ')}`);
    return res.json({ ok: false, missing: env.missing }, 500);
  }

  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(req.headers['x-appwrite-key'] ?? process.env.APPWRITE_FUNCTION_API_KEY);

  const tables = new TablesDB(client);
  const messaging = new Messaging(client);
  const db = { databaseId: env.get('APPWRITE_DATABASE_ID'), tableId: env.get('APPWRITE_TABLE_ID') };

  const creds = {
    stationID: env.get('SOLIS_STATION_ID'),
    cookie: env.get('SOLIS_COOKIE'),
    deviceID: env.get('SOLIS_DEVICE_ID'),
    secret: env.get('SOLIS_SIGNING_SECRET'),
  };

  const state = await loadState(tables, db, log);
  const sent = [];

  const send = async (subject, body) => {
    await messaging.createEmail({
      messageId: ID.unique(),
      subject,
      content: body,
      topics: listEnv('ALERT_TOPIC_IDS'),
      targets: listEnv('ALERT_TARGET_IDS'),
      users: listEnv('ALERT_USER_IDS'),
    });
    log(`sent: ${subject}`);
    sent.push(subject);
  };

  // --- Grid state, from /alarm/list only ---------------------------------
  //
  // Fetched before the station reading so the common case — grid up, nothing
  // to report — costs one request instead of two. That halves this function's
  // load on SolisCloud across a normal day.
  const alarmResult = await fetchAlarms(creds);

  if (alarmResult.kind === SESSION_EXPIRED) {
    // Latched, because this fires on every run until someone signs in again on
    // the Mac and copies the new cookie across. But it must fire at least
    // once: an expired session makes this whole function a silent no-op, and a
    // battery alarm that has quietly stopped working is worse than none.
    if (!state.sessionAlertSent) {
      await send(
        'Solis alerts are DOWN — session expired',
        'The SolisCloud session used by the battery-alert function has expired, so it can no ' +
          'longer read the inverter. No low-battery or grid emails will arrive until it is renewed.\n\n' +
          'Fix: open Preferences in the macOS app, Sign In, then copy the new cookie and device-id ' +
          'into this function\'s SOLIS_COOKIE and SOLIS_DEVICE_ID variables.'
      );
      state.sessionAlertSent = true;
      await saveState(tables, db, state);
    }
    error('SolisCloud session expired');
    return res.json({ ok: false, reason: 'sessionExpired', sent }, 502);
  }

  if (alarmResult.kind !== OK) {
    // Transient. No email: a flaky request is not news, and emailing on it
    // would train the user to ignore this address.
    error(`alarm/list failed: ${alarmResult.detail ?? alarmResult.kind}`);
    return res.json({ ok: false, reason: alarmResult.kind, sent }, 502);
  }

  state.sessionAlertSent = false;

  const gridLoss = alarmResult.alarms.find(isGridLoss);
  const outageNow = FORCING || Boolean(gridLoss);
  if (FORCING) log(`DRY_RUN_FORCE_OUTAGE=${forcedSOC} — simulating a grid outage at ${forcedSOC}%`);
  log(`grid outage: ${outageNow} (alarms: ${alarmResult.alarms.map((a) => a.code).join(',') || 'none'})`);

  // Grid up and it was up last run: nothing to say, and no reason to spend a
  // station read.
  if (!outageNow && !state.outageActive) {
    await saveState(tables, db, state);
    return res.json({ ok: true, outage: false, sent }, 200);
  }

  // --- The reading ------------------------------------------------------
  const stationResult = await fetchStation(creds);
  if (stationResult.kind !== OK) {
    error(`station/detailMix failed: ${stationResult.detail ?? stationResult.kind}`);
    return res.json({ ok: false, reason: stationResult.kind, sent }, 502);
  }

  const data = stationResult.data;
  const soc = FORCING ? forcedSOC : (num(data.batteryPercent) ?? 0);
  const batteryKW = num(data.batteryPowerV2) ?? 0;
  // familyLoadPower reads 0 on this system while the house is genuinely
  // drawing — a live sample had it at 0 with totalLoadPowerOrigin at 230 W and
  // the battery discharging 0.27 kW. Without this fallback an outage email said
  // "House load: 0.00 kW" directly beside "discharging 0.27 kW", which is the
  // self-contradicting-panel bug the app already had once. Same fallback the
  // app uses; note the W -> kW conversion.
  let loadKW = num(data.familyLoadPower) ?? 0;
  if (loadKW === 0) {
    const origin = num(data.totalLoadPowerOrigin);
    if (origin) loadKW = origin / 1000;
  }
  const stationName = data.stationName || 'Solis Station';
  const ageSeconds = readingAge(data);
  const reading = `${stationName} · battery ${fmt(soc, 0)}%` +
    (batteryKW < 0 ? `, discharging ${fmt(-batteryKW, 2)} kW` : batteryKW > 0 ? `, charging ${fmt(batteryKW, 2)} kW` : ', idle') +
    `\nHouse load: ${fmt(loadKW, 2)} kW` +
    `\nReading taken: ${data.dataTimestampStr ?? 'unknown'}${staleNote(ageSeconds)}`;

  // --- Grid restored ----------------------------------------------------
  if (!outageNow) {
    await send(
      `Solis: grid is BACK — battery ${fmt(soc, 0)}%`,
      `Mains power has returned.\n\n${reading}\n\nThe low-battery sequence has been reset; ` +
        'a new outage will start again at 25%.'
    );
    state.outageActive = false;
    state.firedLevels = [];
    await saveState(tables, db, state);
    return res.json({ ok: true, outage: false, restored: true, sent }, 200);
  }

  // --- Outage in progress -----------------------------------------------
  if (!state.outageActive) {
    state.outageActive = true;
    state.firedLevels = [];
    if (process.env.NOTIFY_OUTAGE_START !== 'false') {
      // Sent so the "grid is BACK" email has a matching opener. Without it a
      // restore email can arrive with no preceding message at all, whenever
      // the outage ends before the battery reaches 25%.
      await send(
        `Solis: GRID DOWN — battery ${fmt(soc, 0)}%`,
        `Mains power lost${gridLoss?.beganText ? ` at ${gridLoss.beganText}` : ''}. ` +
          `Running on battery and solar.\n\n${reading}\n\n` +
          `You will get an email at ${LEVELS.join('%, ')}% battery.`
      );
    }
  }

  // Re-arm anything the battery has climbed well clear of.
  state.firedLevels = state.firedLevels.filter((level) => soc < level + REARM_MARGIN);

  // Every level at or below the current SOC that has not fired this outage.
  // The most severe one is what gets sent — a fast drop past three levels
  // should produce one useful email, not three stale ones — but all of them
  // are marked so they cannot fire again on the way down.
  const crossed = LEVELS.filter((level) => soc <= level && !state.firedLevels.includes(level));

  if (crossed.length) {
    const severest = Math.min(...crossed);
    const step = LEVELS.indexOf(severest) + 1;
    const final = step === LEVELS.length;

    state.firedLevels = [...new Set([...state.firedLevels, ...crossed])];
    await send(
      `${final ? '🚨 CRITICAL' : '🔋'} Solis: battery ${fmt(soc, 0)}% on grid outage (${step} of ${LEVELS.length})`,
      `${final
        ? 'Battery is nearly at its cut-off. The inverter will stop supporting the house shortly.'
        : `Battery has fallen to ${severest}% or below while the grid is down.`}\n\n` +
        `${reading}\n\n` +
        `Alert ${step} of ${LEVELS.length}${final ? '' : `. Next email at ${LEVELS[step]}%.`}`
    );
  }

  state.lastSoc = soc;
  await saveState(tables, db, state);
  return res.json({ ok: true, outage: true, soc, fired: state.firedLevels, sent }, 200);
};

// MARK: - State
//
// Appwrite Functions are stateless, so the latches live in one row. Without
// them every run during an outage would re-send every crossed level.

async function loadState(tables, db, log) {
  try {
    const row = await tables.getRow({ ...db, rowId: ROW_ID });
    return {
      firedLevels: parseLevels(row.firedLevels),
      outageActive: Boolean(row.outageActive),
      sessionAlertSent: Boolean(row.sessionAlertSent),
      lastSoc: row.lastSoc ?? null,
    };
  } catch (e) {
    log(`no state row yet (${e.code ?? e.message}); starting clean`);
    return { firedLevels: [], outageActive: false, sessionAlertSent: false, lastSoc: null };
  }
}

async function saveState(tables, db, state) {
  const data = {
    firedLevels: state.firedLevels.join(','),
    outageActive: state.outageActive,
    sessionAlertSent: state.sessionAlertSent,
    lastSoc: state.lastSoc,
  };
  try {
    await tables.updateRow({ ...db, rowId: ROW_ID, data });
  } catch {
    await tables.createRow({ ...db, rowId: ROW_ID, data });
  }
}

const parseLevels = (csv) =>
  String(csv ?? '')
    .split(',')
    .map((s) => Number.parseInt(s, 10))
    .filter((n) => Number.isFinite(n));

// MARK: - Helpers

/**
 * Reading age in seconds, measured server-side.
 *
 * dataTimestamp is when the inverter reported and nowZoneTime is SolisCloud's
 * own clock, both epoch millis — so this cannot be thrown off by a skewed
 * clock at either end. Normal lag is around 3 minutes.
 */
function readingAge(data) {
  const reported = num(data.dataTimestamp);
  if (reported == null) return null;
  const reference = num(data.nowZoneTime) ?? Date.now();
  const age = (reference - reported) / 1000;
  // Negative means the inverter's clock leads the server's; absurdly large
  // means the field is not what we think it is. Neither is evidence of age.
  return age >= 0 && age < 30 * 24 * 3600 ? age : null;
}

const staleNote = (ageSeconds) =>
  ageSeconds != null && ageSeconds > STALE_SECONDS
    ? `\n\n⚠️ This reading is ${Math.round(ageSeconds / 60)} minutes old. The inverter has stopped ` +
      'reporting — likely the house internet is down too, so the real battery level is probably lower.'
    : '';

const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
const fmt = (v, places) => v.toFixed(places);

const listEnv = (name) =>
  (process.env[name] ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

function requireEnv(names) {
  const missing = names.filter((n) => !(process.env[n] ?? '').trim());
  return { missing, get: (n) => process.env[n].trim() };
}
