import AppKit
import WebKit
import CanvasCore

extension RenderResult {
    /// What `canvas.render` returned, its page times mapped by `window`.
    init(_ result: Result<Any, Error>, window: PageClock.Window) {
        switch result {
        case .success(let value):
            guard let object = value as? [String: Any] else {
                error = "render returned no result"
                return
            }
            height = (object["height"] as? NSNumber).map { CGFloat($0.doubleValue) }
            error = object["error"] as? String
            jsStart = (object["jsStart"] as? NSNumber).map { window.clock(pageMilliseconds: $0.doubleValue) }
            jsEnd = (object["jsEnd"] as? NSNumber).map { window.clock(pageMilliseconds: $0.doubleValue) }
        case .failure(let failure):
            error = "render failed: \(WebPage.message(failure))"
        }
    }
}

/// The renderer page in its webview: loads `index.html`, calls the page
/// API, routes page messages to the delegate, and never navigates away.
final class WebPage: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    typealias Completion = (Result<Any, Error>) -> Void

    /// One non-persistent store for every page. WebKit already shares one
    /// process pool between all webviews.
    private static let dataStore = WKWebsiteDataStore.nonPersistent()

    let webView: WKWebView
    let indexURL: URL
    weak var delegate: PanelContentDelegate?

    private(set) var loaded = false
    private var everLoaded = false
    private var loadStarted: UInt64 = 0
    private var pending: [() -> Void] = []

    private typealias Route = (WebPage, [String: Any]) -> Void

    private static let routes: [String: Route] = [
        "painted": { page, _ in page.delegate?.contentDidPaint() },
        "error": { page, body in page.delegate?.contentDidReportError(body["message"] as? String ?? "render error") },
        "size": { page, body in
            guard let height = body["height"] as? NSNumber else { return }
            page.delegate?.contentDidResize(height: CGFloat(height.doubleValue))
        },
        "result": { page, body in page.delegate?.contentDidSubmit(body["value"] ?? NSNull()) },
        "close": { page, body in
            if body["reason"] as? String == "escape" {
                page.delegate?.contentDidRequestEscapeClose()
            } else {
                page.delegate?.contentDidRequestClose()
            }
        },
        "open": { _, body in
            guard let string = body["url"] as? String, let url = URL(string: string) else { return }
            openExternally(url)
        },
        "subscribe": { page, body in
            guard let channel = body["channel"] as? String else { return }
            page.delegate?.contentDidSubscribe(channel: channel, every: (body["every"] as? NSNumber)?.intValue)
        },
        "unsubscribe": { page, body in
            guard let channel = body["channel"] as? String else { return }
            page.delegate?.contentDidUnsubscribe(channel: channel)
        },
        "publish": { page, body in
            guard let channel = body["channel"] as? String else { return }
            page.delegate?.contentDidPublish(channel: channel, value: body["value"] ?? NSNull())
        }
    ]

    init(indexURL: URL) {
        self.indexURL = indexURL
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        config.websiteDataStore = Self.dataStore
        config.suppressesIncrementalRendering = false
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        config.userContentController.add(WeakMessageHandler(self), name: "canvas")
        webView.setValue(false, forKey: "drawsBackground")
        webView.isInspectable = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
    }

    func load() {
        loadStarted = Clock.now()
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
    }

    /// Runs `body` as an async function in the page, once it has loaded.
    func call(_ body: String, arguments: [String: Any] = [:], completion: Completion? = nil) {
        let run = { [weak self] in
            guard let self else { return }
            self.webView.callAsyncJavaScript(
                body, arguments: arguments, in: nil, in: .page, completionHandler: completion)
        }
        if loaded { run() } else { pending.append(run) }
    }

    func render(_ payload: [String: Any], completion: @escaping (RenderResult) -> Void) {
        let before = PageClock.sample()
        call("return canvas.render(p)", arguments: ["p": payload]) { result in
            completion(RenderResult(result, window: PageClock.Window(before, .sample())))
        }
    }

    func tearDown() {
        ChannelHub.shared.remove(self)
        delegate = nil
        pending.removeAll()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "canvas")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
    }

    static func openExternally(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) else { return }
        NSWorkspace.shared.open(url)
    }

    /// The JavaScript exception message when there is one.
    static func message(_ error: Error) -> String {
        let info = (error as NSError).userInfo
        return info["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
    }

    // MARK: Messages

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        guard let route = Self.routes[type] else {
            if type != "rendered" { debugLog("unhandled page message \(type)") }
            return
        }
        route(self, body)
    }

    // MARK: Navigation

    func webView(
        _: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url.isFileURL, action.targetFrame?.isMainFrame == true,
           url.standardizedFileURL.path == indexURL.standardizedFileURL.path {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if action.navigationType == .linkActivated || action.targetFrame?.isMainFrame == true {
            Self.openExternally(url)
        }
    }

    func webView(_: WKWebView, didFinish _: WKNavigation?) {
        loaded = true
        debugLog("page loaded in \(Clock.milliseconds(from: loadStarted, to: Clock.now())) ms")
        let calls = pending
        pending.removeAll()
        calls.forEach { $0() }
        call("canvas.warm()")
        if everLoaded { delegate?.contentDidReload() }
        everLoaded = true
    }

    func webView(_: WKWebView, didFail _: WKNavigation?, withError error: Error) {
        delegate?.contentDidReportError("renderer failed to load: \(error.localizedDescription)")
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation?, withError error: Error) {
        delegate?.contentDidReportError("renderer failed to load: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        debugLog("web content process terminated; reloading")
        ChannelHub.shared.remove(self)
        loaded = false
        load()
    }

    // swiftlint:disable:next function_parameter_count - WKUIDelegate fixes this signature
    func webView(
        _: WKWebView,
        createWebViewWith _: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        if let url = action.request.url { Self.openExternally(url) }
        return nil
    }
}
