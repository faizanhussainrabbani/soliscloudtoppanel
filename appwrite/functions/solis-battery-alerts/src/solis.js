// SolisCloud client — a direct port of Sources/SolisSolarMonitor/SolisAPI.swift.
//
// Ported, not reimplemented, on purpose: the request signing is the one part of
// this project that was only ever verified by reproducing a browser-issued
// signature byte for byte. Rewriting it from the description would throw that
// verification away. If SolisAPI.swift changes, change this to match.

import crypto from 'node:crypto';

// Travels in the clear in every Authorization header, so it is not a secret in
// any useful sense. Same reasoning as the Swift side.
const KEY_ID = '2424';

const BASE = 'https://www.soliscloud.com/api';

/** Result kinds, mirroring SolisFetchResult. */
export const OK = 'ok';
export const SESSION_EXPIRED = 'sessionExpired';
export const API_ERROR = 'apiError';
export const OFFLINE = 'offline';

function computeAuth(bodyJSON, dateStr, path, secret) {
  const contentMD5 = crypto.createHash('md5').update(bodyJSON, 'utf8').digest('base64');
  const stringToSign = `POST\n${contentMD5}\napplication/json\n${dateStr}\n${path}`;
  const mac = crypto.createHmac('sha1', secret).update(stringToSign, 'utf8').digest('base64');
  return { authorization: `WEB ${KEY_ID}:${mac}`, contentMD5 };
}

/**
 * Signs and sends one POST.
 *
 * Body strings are built by hand by every caller, never via JSON.stringify on
 * an object literal: Content-MD5 is computed over these exact bytes, so key
 * order and spacing are part of the contract.
 */
async function post({ path, bodyJSON, stationID, cookie, deviceID, secret }) {
  // Node's toUTCString() is exactly the "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
  // format the Swift DateFormatter produces.
  const dateStr = new Date().toUTCString();
  const auth = computeAuth(bodyJSON, dateStr, path, secret);

  let response;
  try {
    response = await fetch(`${BASE}${path}`, {
      method: 'POST',
      body: bodyJSON,
      headers: {
        'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36',
        Accept: 'application/json, text/plain, */*',
        'Accept-Language': 'en-US,en;q=0.9,ru;q=0.8',
        Authorization: auth.authorization,
        'Content-MD5': auth.contentMD5,
        'Content-Type': 'application/json;charset=UTF-8',
        Date: dateStr,
        Cookie: cookie,
        'device-id': deviceID,
        language: '2',
        origin: 'https://www.soliscloud.com',
        platform: 'Web',
        referer: `https://www.soliscloud.com/overview/plantStation/details/overview/${stationID}`,
        'x-cloud-platform': 'GLY',
      },
      // 15 s, not the app's 30 s. This runs inside an Appwrite function whose
      // own timeout is the hard ceiling, and two of these calls happen in
      // sequence — a 30 s budget each can exceed the function timeout and get
      // killed mid-run, which looks like a SolisCloud fault and isn't. Live
      // calls answer in about a second, so 15 s is already generous.
      signal: AbortSignal.timeout(15_000),
    });
  } catch (e) {
    return { kind: OFFLINE, detail: e.message };
  }

  if (response.status === 401 || response.status === 403) return { kind: SESSION_EXPIRED };
  if (!response.ok) return { kind: API_ERROR, detail: `HTTP ${response.status}` };

  let root;
  try {
    root = await response.json();
  } catch {
    return { kind: OFFLINE, detail: 'unparseable body' };
  }

  const code = String(root.code ?? '');
  if (code === '0' && root.data) return { kind: OK, data: root.data };

  // B0049 is SolisCloud's own "session gone" code, not an HTTP status.
  if (code === '401' || code === '403' || code === 'B0049') return { kind: SESSION_EXPIRED };
  return { kind: API_ERROR, detail: `API Error (${code || 'Err'}) ${root.msg ?? ''}`.trim() };
}

/** /station/detailMix — the reading itself. */
export function fetchStation({ stationID, cookie, deviceID, secret }) {
  const localTime = Date.now();
  const bodyJSON = `{"id":"${stationID}","localTime":${localTime},"localTimeZone":5,"language":"2"}`;
  return post({ path: '/station/detailMix', bodyJSON, stationID, cookie, deviceID, secret });
}

/**
 * /alarm/list — the only trustworthy source of grid state.
 *
 * Nothing in /station/detailMix reports grid health. Measured across both
 * conditions: `state` read 3 whether the grid was fine or absent, and
 * `alarmCount` read 0 *while* the NO-Grid alarm was active. Both obvious
 * candidates are wrong. Do not gate anything on either.
 *
 * `state: 0` in the body selects currently-active alarms.
 */
export async function fetchAlarms({ stationID, cookie, deviceID, secret }) {
  const localTime = Date.now();
  const bodyJSON =
    `{"currentPage":1,"pageSize":10,"state":0,"selectAreaValue":[],` +
    `"faultType":0,"stationId":"${stationID}","pageNo":1,` +
    `"localTime":${localTime},"localTimeZone":5,"language":"2"}`;

  const result = await post({ path: '/alarm/list', bodyJSON, stationID, cookie, deviceID, secret });
  if (result.kind !== OK) return result;

  const records = Array.isArray(result.data.records) ? result.data.records : [];
  const alarms = records
    .filter((r) => r.alarmMsg)
    .map((r) => ({
      code: String(r.alarmCode ?? ''),
      message: String(r.alarmMsg),
      beganText: String(r.alarmBeginTimeStr ?? ''),
    }));
  return { kind: OK, alarms };
}

/**
 * Code 1015 / "NO-Grid" is the inverter's grid-loss alarm, confirmed against a
 * live outage. The message is matched too, in case the code is localised.
 */
export function isGridLoss(alarm) {
  return alarm.code === '1015' || alarm.message.replace(/-/g, '').toLowerCase() === 'nogrid';
}
