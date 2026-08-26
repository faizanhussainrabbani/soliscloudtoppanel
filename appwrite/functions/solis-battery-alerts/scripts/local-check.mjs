// Local auth check. Hits the real SolisCloud API with the real credentials,
// using the same solis.js the function uses — so a pass here means the signing,
// headers and session all work before anything is deployed.
//
//   node scripts/local-check.mjs
//
// Needs no npm install: it imports only src/solis.js, never the Appwrite SDK.
//
// Credentials are read straight from the macOS app's UserDefaults, so they
// never appear in a shell history, a process list or this file. Nothing here
// prints a secret — only its length, which is enough to spot an empty or
// truncated one.

import { execFileSync } from 'node:child_process';
import { fetchAlarms, fetchStation, isGridLoss, OK } from '../src/solis.js';

const DOMAIN = 'com.faizan.SolisSolarMonitor';

const read = (key) => {
  try {
    return execFileSync('defaults', ['read', DOMAIN, key], { encoding: 'utf8' }).trim();
  } catch {
    return '';
  }
};

const creds = {
  stationID: read('station-id'),
  cookie: read('cookie'),
  deviceID: read('device-id'),
  secret: read('api-signing-secret'),
};

console.log('Credentials from UserDefaults:');
for (const [name, value] of Object.entries(creds)) {
  console.log(`  ${name.padEnd(10)} ${value ? `${value.length} chars` : 'MISSING'}`);
}
const missing = Object.entries(creds).filter(([, v]) => !v).map(([k]) => k);
if (missing.length) {
  console.error(`\nCannot continue: ${missing.join(', ')} not set.`);
  process.exit(1);
}

// --- /alarm/list: the grid signal, and the call the function makes first ----
console.log('\n1. POST /alarm/list');
const alarms = await fetchAlarms(creds);
if (alarms.kind !== OK) {
  console.error(`   FAILED (${alarms.kind}) ${alarms.detail ?? ''}`);
  if (alarms.kind === 'sessionExpired') {
    console.error('   The cookie has expired. Sign in again in the app, then re-run.');
  }
  process.exit(1);
}
console.log(`   OK — ${alarms.alarms.length} active alarm(s)`);
for (const a of alarms.alarms) console.log(`     ${a.code} ${a.message} ${a.beganText}`);
const outage = alarms.alarms.some(isGridLoss);
console.log(`   grid outage: ${outage}`);

// --- /station/detailMix: the reading -------------------------------------
console.log('\n2. POST /station/detailMix');
const station = await fetchStation(creds);
if (station.kind !== OK) {
  console.error(`   FAILED (${station.kind}) ${station.detail ?? ''}`);
  process.exit(1);
}
const d = station.data;
const age = d.dataTimestamp && d.nowZoneTime ? (d.nowZoneTime - d.dataTimestamp) / 1000 : null;
console.log('   OK — fields the alert logic reads:');
console.log(`     batteryPercent   ${d.batteryPercent}`);
console.log(`     batteryPowerV2   ${d.batteryPowerV2} (negative = discharging)`);
console.log(`     familyLoadPower  ${d.familyLoadPower}`);
// Printed alongside the raw field because familyLoadPower reads 0 on this
// system while the house is drawing; the resolved figure is what the email
// carries, and seeing only the raw 0 here reads as a fault when it isn't.
const resolvedLoad = d.familyLoadPower || (d.totalLoadPowerOrigin ?? 0) / 1000;
console.log(`     totalLoadPowerOrigin ${d.totalLoadPowerOrigin} W  -> load used: ${resolvedLoad.toFixed(2)} kW`);
console.log(`     dataTimestampStr ${d.dataTimestampStr}`);
console.log(`     reading age      ${age == null ? 'unknown' : `${(age / 60).toFixed(1)} min`}`);

// Station name is the only account-identifying field printed, and it is the one
// that shows the signed request reached the right station.
console.log(`     stationName      ${d.stationName ? 'present' : 'MISSING'}`);

// --- What the function would do with this ---------------------------------
const LEVELS = [25, 23, 21, 19, 17];
const soc = d.batteryPercent ?? 0;
console.log('\n3. Verdict');
if (!outage) {
  console.log('   Grid is up. The function would send nothing and stop after call 1.');
  const would = LEVELS.filter((l) => soc <= l);
  console.log(`   If the grid dropped right now at ${soc}%, it would send: ` +
    (would.length ? `grid-down + level ${Math.min(...would)} (${LEVELS.indexOf(Math.min(...would)) + 1} of 5)`
                  : 'grid-down only'));
} else {
  const would = LEVELS.filter((l) => soc <= l);
  console.log(`   Grid is DOWN at ${soc}%. Would send: ` +
    (would.length ? `level ${Math.min(...would)} (${LEVELS.indexOf(Math.min(...would)) + 1} of 5)` : 'grid-down only'));
}
console.log('\nAuthentication works. Both signed endpoints returned data.');
