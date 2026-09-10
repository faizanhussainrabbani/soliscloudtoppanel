import Foundation
import CryptoKit

enum SolisFetchResult {
    case success(JSONDict)
    case sessionExpired
    case apiError(String)   // message shown in the panel, e.g. "API Error (B0032)"
    case offline
}

/// Port of _computeSolisAuth / _fetchSolarData from extension.js.
enum SolisAPI {
    /// The signing secret is NOT in this repository, by decision.
    ///
    /// It belongs to SolisCloud's web client, not to us. Publishing it would
    /// hand out a vendor secret, and would invite them to rotate it — breaking
    /// this app and anything else built the same way. So it lives in
    /// UserDefaults on the machine that runs the app:
    ///
    ///   defaults write com.faizan.SolisSolarMonitor api-signing-secret -string '…'
    ///
    /// With it unset every request would be signed with an empty key and the
    /// server would answer 401 — indistinguishable from an expired session. So
    /// callers check first and say what's actually wrong. See
    /// SolisMonitor.fetchSolarData.
    ///
    /// keyID stays in source: it travels in the clear in every Authorization
    /// header, so it is not a secret in any useful sense.
    private static let keyID  = "2424"
    private static let path   = "/station/detailMix"
    private static let endpoint = "https://www.soliscloud.com/api/station/detailMix"

    /// URLSession manages the Cookie header itself unless cookie handling is
    /// disabled outright, which would silently drop the captured session
    /// cookie we set by hand below.
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        cfg.httpCookieStorage = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 30
        return URLSession(configuration: cfg)
    }()

    struct Auth {
        let authorization: String
        let contentMD5: String
    }

    static func computeAuth(bodyJSON: String, dateStr: String, path: String = path,
                            secret: String) -> Auth {
        let contentMD5 = Data(Insecure.MD5.hash(data: Data(bodyJSON.utf8))).base64EncodedString()
        let stringToSign = "POST\n\(contentMD5)\napplication/json\n\(dateStr)\n\(path)"
        let mac = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: SymmetricKey(data: Data(secret.utf8))
        )
        return Auth(
            authorization: "WEB \(keyID):\(Data(mac).base64EncodedString())",
            contentMD5: contentMD5
        )
    }

    /// One active inverter alarm, from /alarm/list.
    struct Alarm: Equatable {
        let code: String        // "1015"
        let message: String     // "NO-Grid"
        let level: String       // "1"
        let beganAt: Date?
        let beganText: String   // "18/08/2026 18:33 (UTC+05:00)"
    }

    /// Active alarms, or nil if the call failed.
    ///
    /// This endpoint exists because nothing in /station/detailMix reports grid
    /// health. Verified against a live grid outage: `state` read 3 and
    /// `alarmCount` read **0** while this endpoint returned code 1015
    /// "NO-Grid", begun 18:33. Both of the fields the app previously reached
    /// for were wrong at the same moment.
    ///
    /// `state: 0` in the request body selects currently-active alarms; the
    /// signing is the same scheme as the station call, just a different path
    /// (confirmed by reproducing a browser-issued signature byte for byte).
    static func fetchAlarms(stationID: String, cookie: String, deviceID: String,
                            secret: String) async -> [Alarm]? {
        let localTime = Int(Date().timeIntervalSince1970 * 1000)
        // Hand-built for the same reason as the station body: Content-MD5 is
        // computed over these exact bytes, so key order and spacing matter.
        let bodyJSON = "{\"currentPage\":1,\"pageSize\":10,\"state\":0,\"selectAreaValue\":[],"
            + "\"faultType\":0,\"stationId\":\"\(stationID)\",\"pageNo\":1,"
            + "\"localTime\":\(localTime),\"localTimeZone\":5,\"language\":\"2\"}"

        guard case .success(let payload) = await post(
            path: "/alarm/list",
            endpoint: "https://www.soliscloud.com/api/alarm/list",
            bodyJSON: bodyJSON, stationID: stationID, cookie: cookie, deviceID: deviceID,
            secret: secret
        ) else { return nil }

        guard let records = payload.array("records") else { return [] }
        return records.compactMap { record in
            guard let message = record.str("alarmMsg"), !message.isEmpty else { return nil }
            var began: Date?
            if let millis = record.num("alarmBeginTime"), millis > 0 {
                began = Date(timeIntervalSince1970: millis / 1000)
            }
            return Alarm(
                code: record.str("alarmCode") ?? "",
                message: message,
                level: record.str("alarmLevel") ?? "",
                beganAt: began,
                beganText: record.str("alarmBeginTimeStr") ?? ""
            )
        }
    }

    /// The handful of fields worth having from /inverter/detail, which returns
    /// 809 of them. Everything here changes slowly or matters rarely, so this
    /// is fetched on the throttled slot rather than per poll.
    struct InverterDetail {
        /// socDischargeSet — the on-grid discharge floor, as configured on the
        /// unit. Replaces a number the user had to type.
        let dischargeFloorSOC: Double?
        /// epsDDepth and offGridDDepth — two more floor-shaped settings that
        /// disagree with socDischargeSet (15 / 20 / 30 on this system). Which
        /// one governs when is not documented in the response, so both are
        /// carried and the choice is made where the consequences are known.
        let epsFloorSOC: Double?
        let offGridFloorSOC: Double?
        /// batteryHealthSoh, percent. Nameplate capacity x this = what the
        /// pack can actually hold today.
        let batteryHealthSOH: Double?
        /// inverterTemperature, °C, internal — not ambient. Solis documents
        /// internal 110°C as the shutdown point and says readings above 85°C
        /// are normal, so this is only worth surfacing when it's genuinely high.
        let internalTemperature: Double?
        // --- Grid-presence candidates, captured but not yet acted on --------
        // Measured only during an outage so far: uAc1/uAc2/uAc3 and fac all
        // read 0, and currentState read 1015 (the NO-Grid alarm code). None can
        // be trusted until a grid-present sample shows what they read normally.
        // `data.state` looked just as convincing from one sample and was wrong.
        let gridVoltage: Double?
        let gridFrequency: Double?
        let currentState: String?
        /// batteryAcvSet / batteryFcvSet — the absorption and float setpoints,
        /// 56.1 V and 53.5 V on this system (3.506 and 3.344 V/cell at 16S).
        ///
        /// Carried so the full-charge row can tell a real top-of-charge from a
        /// coulomb-counted 100%: LFP cells only balance when driven up towards
        /// absorption, and a BMS can report 100% while the pack sits at float.
        /// Static settings, so the throttled fetch is fine for them.
        let absorptionVoltage: Double?
        let floatVoltage: Double?
        /// batteryUvpSet — the inverter's own under-voltage cut-off, 42 V here.
        ///
        /// Used to tell an empty pack from an unreadable one. Verified to
        /// survive a live Batt_Comm_FAIL intact while every BMS-sourced field
        /// around it collapsed to 0, which is exactly what makes it a usable
        /// reference during the fault.
        let underVoltageSet: Double?
    }

    static func fetchInverterDetail(inverterID: String, cookie: String, deviceID: String,
                                    secret: String) async -> InverterDetail? {
        let localTime = Int(Date().timeIntervalSince1970 * 1000)
        let bodyJSON = "{\"id\":\"\(inverterID)\",\"localTime\":\(localTime),\"localTimeZone\":5,\"language\":\"2\"}"

        guard case .success(let payload) = await post(
            path: "/inverter/detail",
            endpoint: "https://www.soliscloud.com/api/inverter/detail",
            bodyJSON: bodyJSON, stationID: inverterID, cookie: cookie, deviceID: deviceID,
            secret: secret
        ) else { return nil }

        return InverterDetail(
            dischargeFloorSOC: payload.num("socDischargeSet"),
            epsFloorSOC: payload.num("epsDDepth"),
            offGridFloorSOC: payload.num("offGridDDepth"),
            batteryHealthSOH: payload.num("batteryHealthSoh"),
            internalTemperature: payload.num("inverterTemperature"),
            gridVoltage: payload.num("uAc1"),
            gridFrequency: payload.num("fac"),
            currentState: payload.str("currentState"),
            absorptionVoltage: payload.num("batteryAcvSet"),
            floatVoltage: payload.num("batteryFcvSet"),
            underVoltageSet: payload.num("batteryUvpSet")
        )
    }

    static func fetch(stationID: String, cookie: String, deviceID: String,
                      secret: String) async -> SolisFetchResult {
        // Built by hand rather than via JSONEncoder: Content-MD5 is computed
        // over these exact bytes, so key order and spacing must match what
        // JSON.stringify produced on the GNOME side.
        let localTime = Int(Date().timeIntervalSince1970 * 1000)
        let bodyJSON = "{\"id\":\"\(stationID)\",\"localTime\":\(localTime),\"localTimeZone\":5,\"language\":\"2\"}"

        return await post(path: path, endpoint: endpoint, bodyJSON: bodyJSON,
                          stationID: stationID, cookie: cookie, deviceID: deviceID,
                          secret: secret)
    }

    /// Signs and sends one POST. Shared by both endpoints so the header set,
    /// the error mapping and the session-expiry handling can't drift apart.
    private static func post(path: String, endpoint: String, bodyJSON: String,
                             stationID: String, cookie: String, deviceID: String,
                             secret: String) async -> SolisFetchResult {
        let dateStr = HTTPDate.now()
        let auth = computeAuth(bodyJSON: bodyJSON, dateStr: dateStr, path: path, secret: secret)

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.httpBody = Data(bodyJSON.utf8)

        let headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36",
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "en-US,en;q=0.9,ru;q=0.8",
            "Authorization": auth.authorization,
            "Content-MD5": auth.contentMD5,
            "Content-Type": "application/json;charset=UTF-8",
            "Date": dateStr,
            "Cookie": cookie,
            "device-id": deviceID,
            "language": "2",
            "origin": "https://www.soliscloud.com",
            "platform": "Web",
            "referer": "https://www.soliscloud.com/overview/plantStation/details/overview/\(stationID)",
            "x-cloud-platform": "GLY",
        ]
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard statusCode == 200 else {
                if statusCode == 401 || statusCode == 403 { return .sessionExpired }
                return .apiError("HTTP \(statusCode)")
            }

            guard let object = try? JSONSerialization.jsonObject(with: data),
                  let root = object as? [String: Any] else {
                return .offline
            }

            let json = JSONDict(root)
            let code = json.str("code") ?? ""

            if code == "0", let payload = json.dict("data") {
                return .success(payload)
            }

            NSLog("SolisSolarMonitor API Code: \(code), Msg: \(json.str("msg") ?? "")")

            // Z0001 is SolisCloud's "Login has expired. Please login again",
            // which is a session problem wearing an opaque code. It was missing
            // from this list, so a plain expiry surfaced in the menu bar as
            // "API Error (Z0001)" — cryptic, and it bypassed the session flow
            // that stops polling and offers a sign-in.
            //
            // The message is also matched, because the code list is
            // undocumented and guessing the next one wrong has the same cost.
            let expiredMessage = (json.str("msg") ?? "").lowercased()
            if code == "401" || code == "403" || code == "B0049" || code == "Z0001"
                || expiredMessage.contains("login has expired")
                || expiredMessage.contains("please login") {
                return .sessionExpired
            }
            return .apiError("API Error (\(code.isEmpty ? "Err" : code))")
        } catch {
            NSLog("SolisSolarMonitor: Fetch error - \(error.localizedDescription)")
            return .offline
        }
    }
}
