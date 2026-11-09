import AppKit
import CanvasCore

/// What a panel's content reports to its controller, whichever renderer
/// draws it. Main thread.
protocol PanelContentDelegate: AnyObject {
    /// The page finished loading again after its content process died.
    func contentDidReload()
    func contentDidPaint()
    func contentDidReportError(_ message: String)
    func contentDidResize(height: CGFloat)
    func contentDidSubmit(_ value: Any)
    func contentDidRequestClose()
    /// Esc asked to close, as opposed to × or `close()`.
    func contentDidRequestEscapeClose()
    /// A later change (data, an event, a channel push) produced a tree only
    /// WebKit can draw. Nothing was drawn for it.
    func contentNeedsWeb()
    /// `every` is in milliseconds, for `canvas.sys.*`.
    func contentDidSubscribe(channel: String, every: Int?)
    func contentDidUnsubscribe(channel: String)
    func contentDidPublish(channel: String, value: Any, persist: Bool)
    /// A task checkbox in a Markdown panel was clicked.
    func contentDidToggleTask(line: Int, checked: Bool)
}

/// The `task` message's body: `{line, checked}`.
struct TaskClick {
    let line: Int
    let checked: Bool

    init?(_ body: [String: Any]) {
        guard let line = (body["line"] as? NSNumber)?.intValue, line >= 0,
              let checked = (body["checked"] as? NSNumber)?.boolValue else { return nil }
        self.line = line
        self.checked = checked
    }
}

extension PanelContentDelegate {
    func contentDidReload() {}
    func contentDidPaint() {}
    func contentDidRequestEscapeClose() { contentDidRequestClose() }
    func contentNeedsWeb() {}
    func contentDidToggleTask(line _: Int, checked _: Bool) {}
}

/// What a render returned. Times are `Clock` nanoseconds.
struct RenderResult {
    /// The natural height of the whole surface: header, content and footer.
    var height: CGFloat?
    var error: String?
    /// The content needs WebKit; nothing was drawn for it.
    var needsWeb = false
    var jsStart: UInt64?
    var jsEnd: UInt64?
}

/// A panel's content: the WebKit page or a native surface. Hosts swap
/// contents between panels, so a content never assumes its window.
protocol PanelContent: ChannelSink {
    var renderer: Renderer { get }
    /// Fills the panel surface; also the first responder when focused.
    var view: NSView { get }
    var delegate: PanelContentDelegate? { get set }
    /// Whether a new panel waits for `contentDidPaint` before it shows.
    var revealsOnPaint: Bool { get }
    /// Whether the content's script has timers pending, so it would keep
    /// running while hidden.
    var hasTimers: Bool { get }

    /// `payload` is `{kind, source, title?, data?, buttons?, wait, theme?, accent?}`.
    func render(_ payload: [String: Any], completion: @escaping (RenderResult) -> Void)
    /// New data props, keeping state; the completion gets the new height.
    func setData(_ data: Any, completion: ((CGFloat?) -> Void)?)
    func setAccent(_ accent: String)
    /// The light or dark look `theme: auto` resolved to.
    func setMode(_ mode: ThemeMode)
    /// Clears content and state so a pooled host can serve another panel.
    func reset()
    func tearDown()
    /// Lays out what the last render drew, right before the panel shows.
    func prepareToShow()
    func consoleError(_ message: String)
    /// Runs `js` as a function body in the content's script context
    /// (`eval`, tests only).
    func evaluate(_ js: String, completion: @escaping (Result<Any, Error>) -> Void)
}
