import AppKit
import CanvasCore

/// A panel drawn natively: a context from the runtime, its ops applied to a
/// `ViewTree`, and the kit's SwiftUI surface in a hosting view. Main thread.
///
/// The height comes from the hosting view's layout after every commit. A
/// context that ran over the time limit is retired and replaced, and its
/// subscriptions dropped. Once the tree needs WebKit, the panel moves to a
/// page, so whatever the context still sends or is sent is dropped until
/// the next render.
final class NativePanelContent: PanelContent {
    let renderer = Renderer.native
    let revealsOnPaint = false
    weak var delegate: PanelContentDelegate?

    private let contexts: () -> NativeContext
    private(set) var context: NativeContext?
    private let drawing: NativePanelSurface
    /// Calls in flight; their completions measure the commits they caused.
    private var calls = 0
    /// Bumped when the context is dropped, so its late completions are ignored.
    private var generation = 0
    private var rendered = false
    private var measurePending = false
    private(set) var fellBack = false

    var view: NSView { drawing.hosting }
    var receivesPushes: Bool { delegate != nil }
    var hasTimers: Bool { context?.hasTimers ?? false }
    var tree: ViewTree { drawing.tree }
    var surface: NativeSurface { drawing.surface }
    var lastHeight: CGFloat? { drawing.lastHeight }

    /// `contexts` gives a ready context; it's called again to replace one
    /// that hit the time limit.
    init(contexts: @escaping () -> NativeContext, size: NSSize = PanelHost.parkingFrame.size) {
        self.contexts = contexts
        drawing = NativePanelSurface(size: size)
        drawing.events = self
        drawing.link.delegate = self
        drawing.link.didApply = { [weak self] in self?.committed() }
        drawing.hosting.onWidthChange = { [weak self] in self?.scheduleMeasure() }
    }

    // MARK: Calls

    func render(_ payload: [String: Any], completion: @escaping (RenderResult) -> Void) {
        let context = attachContext()
        drawing.clearError()
        fellBack = false
        drawing.title = payload["title"] as? String ?? ""
        if let accent = payload["accent"] as? String { drawing.setAccent(accent) }
        calls += 1
        let generation = generation
        context.render(payload) { [weak self] result in
            guard let self, generation == self.generation else { return completion(RenderResult(result)) }
            self.calls -= 1
            completion(self.finishRender(result))
        }
    }

    func setData(_ data: Any, completion: ((CGFloat?) -> Void)?) {
        guard let context = liveContext else {
            completion?(nil)
            return
        }
        let done: () -> Void = { [weak self] in completion?(self?.lastHeight) }
        perform(on: context, { $0.setData(data, completion: $1) }, then: done)
    }

    func push(_ batch: [[String: Any]], completion: @escaping () -> Void) {
        guard let context = liveContext else { return completion() }
        perform(on: context, { $0.push(batch, completion: $1) }, then: completion)
    }

    func call(_ function: Int, arguments: [Any]) {
        guard let context = liveContext else { return }
        perform(on: context, { $0.invoke(function, arguments: arguments, completion: $1) }, then: {})
    }

    func setAccent(_ accent: String) {
        drawing.setAccent(accent)
    }

    func setMode(_ mode: ThemeMode) {
        drawing.setMode(mode)
    }

    func reset() {
        ChannelHub.shared.remove(self)
        dropContext()
        drawing.rebuild(title: "")
        rendered = false
        fellBack = false
    }

    func tearDown() {
        ChannelHub.shared.remove(self)
        delegate = nil
        drawing.events = nil
        dropContext()
    }

    func prepareToShow() {
        drawing.hosting.layoutSubtreeIfNeeded()
    }

    func consoleError(_ message: String) {
        debugLog("[native error] \(message)")
    }

    func evaluate(_ js: String, completion: @escaping (Result<Any, Error>) -> Void) {
        guard let context else { return completion(.failure(NativeEvalError(message: "no native context"))) }
        context.evaluate(js) { result in
            if result.value == nil, let error = result.error {
                completion(.failure(NativeEvalError(message: error)))
            } else {
                completion(.success(result.value ?? NSNull()))
            }
        }
    }

    // MARK: Context

    /// The context, unless the tree has fallen back to WebKit.
    private var liveContext: NativeContext? {
        fellBack ? nil : context
    }

    /// Runs a call after the first render. Errors and `needsWeb` from it
    /// arrive as posted messages; only the time limit is reported here.
    private func perform(
        on context: NativeContext,
        _ call: (NativeContext, @escaping (NativeResult) -> Void) -> Void,
        then done: @escaping () -> Void
    ) {
        calls += 1
        let generation = generation
        call(context) { [weak self] result in
            guard let self, generation == self.generation else { return done() }
            self.calls -= 1
            if result.timedOut, let message = result.error {
                self.retire(message)
            } else {
                self.reportHeight()
            }
            done()
        }
    }

    @discardableResult
    private func attachContext() -> NativeContext {
        if let context { return context }
        let context = contexts()
        context.delegate = drawing.link
        self.context = context
        return context
    }

    private func dropContext() {
        generation += 1
        calls = 0
        context?.delegate = nil
        context?.tearDown()
        context = nil
    }

    /// The time limit stopped a call: the context is mid-render and unusable.
    func retire(_ message: String) {
        debugLog("native context retired: \(message)")
        ChannelHub.shared.remove(self)
        dropContext()
        drawing.rebuild(title: drawing.title)
        drawing.showError(message)
        attachContext()
        reportHeight()
    }

    private func finishRender(_ result: NativeResult) -> RenderResult {
        if result.timedOut, let message = result.error {
            retire(message)
        } else if let message = result.error, !result.needsWeb {
            drawing.showError(message)
        }
        rendered = !result.needsWeb
        fellBack = result.needsWeb
        let height = result.needsWeb ? nil : drawing.measure()
        return RenderResult(height: height, error: result.error, needsWeb: result.needsWeb,
                            jsStart: result.jsStart, jsEnd: result.jsEnd)
    }

    /// A later change needs WebKit. The first render's fallback travels in
    /// its result instead.
    func signalNeedsWeb() {
        guard !fellBack else { return }
        fellBack = true
        delegate?.contentNeedsWeb()
    }

    // MARK: Height

    /// A commit outside any call (an effect, a timer): measure once the
    /// messages queued with it have arrived.
    private func committed() {
        if calls == 0 { scheduleMeasure() }
    }

    private func scheduleMeasure() {
        guard rendered, !measurePending else { return }
        measurePending = true
        DispatchQueue.main.async { [weak self] in
            self?.measurePending = false
            self?.reportHeight()
        }
    }

    private func reportHeight() {
        guard rendered, !fellBack else { return }
        let before = drawing.lastHeight
        let height = drawing.measure()
        if height != before { delegate?.contentDidResize(height: height) }
    }
}

struct NativeEvalError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension RenderResult {
    /// A native result whose content was dropped while the call ran.
    init(_ result: NativeResult) {
        self.init(error: result.error, needsWeb: result.needsWeb, jsStart: result.jsStart, jsEnd: result.jsEnd)
    }
}
