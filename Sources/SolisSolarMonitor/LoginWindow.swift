import SwiftUI
import WebKit
import AppKit

/// Port of _openLoginWindow() from prefs.js.
///
/// GNOME hooked WebKit's `resource-load-started` signal to read the
/// Authorization / device-id headers off the first post-login API call.
/// WKWebView exposes no equivalent for XHR/fetch subresources, so the same
/// headers are captured by wrapping XMLHttpRequest and fetch in the page and
/// posting them back over a script message handler. HttpOnly cookies still
/// come from the cookie store, exactly as before.
@MainActor
final class LoginWindowController: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {


    @Published var statusIcon = "🌐"
    @Published var statusText = "Log in to SolisCloud — navigate to your station overview page"
    @Published var infoBannerText = "⏳ Log in — credentials will be captured automatically after login"
    @Published var infoBannerVisible = true
    @Published var successBannerVisible = false
    @Published var cancelButtonTitle = "Cancel"
    @Published var progress: Double = 0
    @Published var progressVisible = false

    private(set) var webView: WKWebView!
    private var window: NSWindow?
    private var observations: [NSKeyValueObservation] = []

    private let settings = SolisSettings.shared
    private var loggedIn = false
    private var captured = false
    private var capturedDeviceID = ""

    private static var current: LoginWindowController?

    /// The long numeric run in a station URL. Requires 12+ digits so ordinary
    /// path numbers and query values can't be mistaken for it, and returns nil
    /// rather than a guess when the URL isn't a station page — a wrong ID would
    /// fail every request afterwards with no obvious cause.
    static func stationID(fromURL uri: String) -> String? {
        guard uri.contains("soliscloud.com") else { return nil }
        let candidates = uri.split(whereSeparator: { !$0.isNumber })
        return candidates.first(where: { $0.count >= 12 }).map(String.init)
    }

    // MARK: - Presentation

    static func show(parent: NSWindow?) {
        if let existing = current, let window = existing.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = LoginWindowController()
        current = controller
        controller.present(parent: parent)
    }

    private func present(parent: NSWindow?) {
        buildWebView()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Login to SolisCloud"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LoginWindowView(controller: self))
        // The controller is its own window delegate, so windowWillClose runs
        // cleanup() no matter how the window closes — the traffic-light
        // button included, not just the Cancel/auto-close code path.
        window.delegate = self
        self.window = window

        if let parent {
            parent.addChildWindow(window, ordered: .above)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.load(URLRequest(url: URL(string: "https://www.soliscloud.com")!))
    }

    /// Just closes the window — windowWillClose does the actual teardown,
    /// so every close path (this, the auto-close timer, the traffic-light
    /// button) funnels through the same cleanup, exactly once.
    func close() {
        window?.close()
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            if let closingWindow = notification.object as? NSWindow {
                closingWindow.parent?.removeChildWindow(closingWindow)
            }
            cleanup()
        }
    }

    /// Idempotent — may run more than once if `close()` and the delegate
    /// callback both fire for the same close.
    private func cleanup() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: "solisAuth")
        window = nil
        Self.current = nil
    }

    // MARK: - WebView

    private func buildWebView() {
        let controller = WKUserContentController()
        // A proxy, not `self` — WKUserContentController retains its message
        // handler strongly, and self owns the webView that owns this
        // controller. Handing it `self` directly is a retain cycle; the
        // proxy holds only a weak reference back.
        controller.add(ScriptMessageProxy(target: self), name: "solisAuth")
        controller.addUserScript(WKUserScript(
            source: Self.headerCaptureScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        let configuration = WKWebViewConfiguration()
        // Persistent store, so the session survives prefs-window restarts.
        configuration.websiteDataStore = .default()
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        self.webView = webView

        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.progress = webView.estimatedProgress
                    self.progressVisible = webView.estimatedProgress > 0 && webView.estimatedProgress < 1
                }
            },
            webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.window?.title = webView.title?.isEmpty == false ? webView.title! : "SolisCloud"
                }
            },
            webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                Task { @MainActor in self?.urlDidChange(webView.url?.absoluteString ?? "") }
            },
        ]
    }

    private func urlDidChange(_ uri: String) {
        statusText = uri.count > 80 ? String(uri.prefix(77)) + "…" : uri

        // The station ID comes from whichever station page you open, rather
        // than a constant in source.
        //
        // It used to be hardcoded, with a comment saying it "will not change" —
        // true of one installation and false of every other, and it put an
        // account identifier in a file destined for a public repository. The
        // sign-in flow already asks you to navigate to your station, and the
        // URL of that page carries the ID, so it can simply be read:
        //
        //   .../overview/plantStation/details/overview/<stationId>
        if let found = Self.stationID(fromURL: uri), found != settings.stationID {
            settings.stationID = found
            NSLog("%@", "SolisSolarMonitor: captured station ID from \(uri)")
        }

        // Detect post-login navigation: the URL moves away from /login
        let isLoginPage = uri.isEmpty
            || uri.contains("/login")
            || uri == "https://www.soliscloud.com/"

        guard !isLoginPage, !loggedIn else { return }
        loggedIn = true
        infoBannerText = "⏳ Logged in — waiting for session token…"

        // Dump everything in localStorage and sessionStorage
        let js = """
        (function() {
            try {
                const ls = {};
                for (let i = 0; i < localStorage.length; i++) {
                    const k = localStorage.key(i);
                    ls[k] = localStorage.getItem(k);
                }
                const ss = {};
                for (let i = 0; i < sessionStorage.length; i++) {
                    const k = sessionStorage.key(i);
                    ss[k] = sessionStorage.getItem(k);
                }
                return JSON.stringify({ localStorage: ls, sessionStorage: ss });
            } catch(e) {
                return JSON.stringify({ error: e.message });
            }
        })()
        """
        webView.evaluateJavaScript(js) { result, error in
            if let error {
                NSLog("SolisPrefs: JS eval error — \(error.localizedDescription)")
            } else if let raw = result as? String {
                NSLog("SolisPrefs [localStorage dump]: \(String(raw.prefix(500)))")
            }
        }
    }

    // MARK: - Header capture

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard loggedIn, !captured,
              let body = message.body as? [String: Any] else { return }

        let authorization = body["authorization"] as? String ?? ""
        let deviceID = body["deviceId"] as? String ?? ""

        // Need at least the Authorization to know we are authenticated
        guard !authorization.isEmpty else { return }

        if !deviceID.isEmpty {
            capturedDeviceID = deviceID
            settings.deviceID = deviceID
        }
        settings.authorization = authorization

        // Pull the real cookie jar — HttpOnly cookies are invisible to page JS.
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self, !self.captured else { return }

                let relevant = cookies.filter { $0.domain.contains("soliscloud.com") }
                let cookieString = relevant
                    .map { "\($0.name)=\($0.value)" }
                    .joined(separator: "; ")

                guard !cookieString.isEmpty else { return }

                self.settings.cookie = cookieString
                NSLog("SolisPrefs: Captured — \(relevant.count) cookies, device-id: \(self.capturedDeviceID)")

                self.captured = true
                self.infoBannerVisible = false
                self.successBannerVisible = true
                self.statusText = "✅ Session credentials captured!"
                self.statusIcon = "✅"
                self.cancelButtonTitle = "Close"

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                    self?.close()
                }
            }
        }
    }

    // MARK: - WKNavigationDelegate

    /// Mirrors TLSErrorsPolicy.IGNORE on the GNOME login session, so
    /// corporate/self-signed certs don't block login. Scoped to this
    /// WebView only — the API client keeps normal TLS validation.
    nonisolated func webView(_ webView: WKWebView,
                             didReceive challenge: URLAuthenticationChallenge,
                             completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // MARK: - Injected script

    private static let headerCaptureScript = """
    (function() {
        if (window.__solisHooked) return;
        window.__solisHooked = true;

        function absolute(u) {
            if (!u) return '';
            u = String(u);
            if (u.charAt(0) === '/') return location.origin + u;
            if (u.indexOf('http') !== 0) return location.origin + '/' + u;
            return u;
        }

        function report(url, headers) {
            try {
                url = absolute(url);
                if (url.indexOf('soliscloud.com/api/') === -1) return;
                var auth = headers['authorization'] || '';
                var dev  = headers['device-id'] || '';
                if (!auth) return;
                window.webkit.messageHandlers.solisAuth.postMessage({
                    authorization: auth, deviceId: dev, url: url
                });
            } catch (e) {}
        }

        var origOpen = XMLHttpRequest.prototype.open;
        var origSet  = XMLHttpRequest.prototype.setRequestHeader;
        var origSend = XMLHttpRequest.prototype.send;

        XMLHttpRequest.prototype.open = function(method, url) {
            this.__solisUrl = url;
            this.__solisHeaders = {};
            return origOpen.apply(this, arguments);
        };
        XMLHttpRequest.prototype.setRequestHeader = function(key, value) {
            try {
                this.__solisHeaders = this.__solisHeaders || {};
                this.__solisHeaders[String(key).toLowerCase()] = value;
            } catch (e) {}
            return origSet.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function() {
            try { report(this.__solisUrl, this.__solisHeaders || {}); } catch (e) {}
            return origSend.apply(this, arguments);
        };

        var origFetch = window.fetch;
        if (origFetch) {
            window.fetch = function(input, init) {
                try {
                    var url = (typeof input === 'string') ? input : (input && input.url);
                    var headers = {};
                    var source = (init && init.headers) || (input && input.headers);
                    if (source) {
                        if (typeof source.forEach === 'function') {
                            source.forEach(function(v, k) { headers[String(k).toLowerCase()] = v; });
                        } else {
                            Object.keys(source).forEach(function(k) {
                                headers[String(k).toLowerCase()] = source[k];
                            });
                        }
                    }
                    report(url, headers);
                } catch (e) {}
                return origFetch.apply(this, arguments);
            };
        }
    })();
    """
}

/// Stands in for the controller as WKUserContentController's script message
/// handler. WKUserContentController retains its handler strongly; handing it
/// the controller directly — which owns the webView that owns this same
/// controller — is a retain cycle. This proxy holds only a weak reference,
/// so the cycle never forms.
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    private weak var target: LoginWindowController?

    init(target: LoginWindowController) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

// MARK: - Window chrome

private struct LoginWindowView: View {
    @ObservedObject var controller: LoginWindowController

    var body: some View {
        VStack(spacing: 0) {
            // ---- Top bar ----
            HStack(spacing: 8) {
                Text(controller.statusIcon)
                Text(controller.statusText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(controller.cancelButtonTitle) { controller.close() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            // ---- Banners ----
            if controller.infoBannerVisible {
                Banner(text: controller.infoBannerText, tint: Color.accentColor.opacity(0.18))
            }
            if controller.successBannerVisible {
                Banner(text: "✅ Credentials captured! Closing…", tint: Color.solisOnline.opacity(0.25))
            }

            // ---- WebView ----
            WebViewRepresentable(webView: controller.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ---- Progress ----
            if controller.progressVisible {
                ProgressView(value: controller.progress)
                    .progressViewStyle(.linear)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

private struct Banner: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint)
    }
}

private struct WebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
