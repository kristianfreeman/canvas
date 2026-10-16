import AppKit
import CanvasCore

/// The page as a panel's content: the page API behind `PanelContent`.
extension WebPage: PanelContent {
    var renderer: Renderer { .web }
    var view: NSView { webView }
    var revealsOnPaint: Bool { true }
    var hasTimers: Bool { false }
    var receivesPushes: Bool { delegate != nil }

    /// The completion gets the page's new natural height.
    func setData(_ data: Any, completion: ((CGFloat?) -> Void)?) {
        call("return canvas.setData(d)", arguments: ["d": data]) { result in
            let height = (try? result.get() as? [String: Any])?["height"] as? NSNumber
            completion?(height.map { CGFloat($0.doubleValue) })
        }
    }

    func setAccent(_ accent: String) {
        call("canvas.setAccent(a)", arguments: ["a": accent])
    }

    /// The page follows its window's appearance through `prefers-color-scheme`.
    func setMode(_: ThemeMode) {}

    func reset() {
        ChannelHub.shared.remove(self)
        call("canvas.reset()")
    }

    func push(_ batch: [[String: Any]], completion: @escaping () -> Void) {
        call("canvas.push(b)", arguments: ["b": batch]) { _ in completion() }
    }

    func prepareToShow() {}

    func consoleError(_ message: String) {
        call("console.error(m)", arguments: ["m": message])
    }

    func evaluate(_ js: String, completion: @escaping (Result<Any, Error>) -> Void) {
        call(js, completion: completion)
    }
}
