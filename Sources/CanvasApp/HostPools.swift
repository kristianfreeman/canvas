import AppKit
import CanvasCore

/// Where panels come from: a pool per renderer and the route cache that
/// picks one. Native goes first; content that needed WebKit before goes
/// straight there. Main thread.
final class HostPools {
    let web: WarmPool
    let native: WarmPool?
    let runtime: NativeRuntime?
    let indexURL: URL
    private var routes = RouteCache()

    /// Without a runtime (no `native.js`), every panel uses WebKit.
    init(indexURL: URL, policy: WarmPolicy, runtime: NativeRuntime?) {
        self.indexURL = indexURL
        self.runtime = runtime
        web = WarmPool(renderer: .web, rules: .web(policy)) { PanelHost.web(indexURL: indexURL) }
        native = runtime.map { runtime in
            WarmPool(renderer: .native, rules: .native) { PanelHost.native { runtime.takeContext() } }
        }
    }

    var hasWebRenderer: Bool { FileManager.default.fileExists(atPath: indexURL.path) }

    func route(for request: ShowRequest) -> Renderer {
        guard native != nil else { return .web }
        return routes.route(path: request.path, source: request.source)
    }

    /// How a native render of `request` went.
    func record(_ renderer: Renderer, for request: ShowRequest) {
        routes.record(renderer, path: request.path, source: request.source)
    }

    func pool(for renderer: Renderer) -> WarmPool {
        renderer == .native ? native ?? web : web
    }

    func take(_ renderer: Renderer) -> (host: PanelHost, pooled: Bool) {
        pool(for: renderer).take()
    }

    func recycle(_ host: PanelHost) {
        pool(for: host.renderer).recycle(host)
    }

    /// The parked hosts, the runtime's ready context, and a SwiftUI warm-up
    /// once the main loop is idle.
    func fill() {
        web.fill()
        guard let native, let runtime else { return }
        runtime.prepare()
        native.fill()
        MainIdle.once {
            let milliseconds = NativePrewarm.run()
            debugLog("SwiftUI prewarm took \(String(format: "%.1f", milliseconds)) ms")
        }
    }

    func refillWhenIdle() {
        web.refillWhenIdle()
        native?.refillWhenIdle()
    }

    func panelsChanged() {
        web.panelsChanged()
        native?.panelsChanged()
    }

    /// Memory pressure: the WebKit page goes; native hosts are cheap.
    func trim() {
        web.trim()
    }
}
