import CanvasCore
import Foundation
import JavaScriptCore

/// The native renderer's shared state: one `JSVirtualMachine` for every
/// context, the bundle source, and one context kept evaluated and ready,
/// like the old warm page (docs/native.md, Runtime).
final class NativeRuntime {
    /// What each context evaluates. Read from any thread.
    struct Bundle {
        let machine: JSVirtualMachine
        let source: String
        let url: URL
        /// Seconds each call into a context may run.
        let timeLimit: TimeInterval
    }

    let bundle: Bundle
    private var ready: NativeContext?

    /// Loads `native.js` from the same web directory as `index.html`.
    init(webDir: URL = Paths.webDir, timeLimit: TimeInterval = 2) throws {
        let url = webDir.appendingPathComponent("native.js")
        let source = try String(contentsOf: url, encoding: .utf8)
        guard let machine = JSVirtualMachine() else {
            throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "no JavaScriptCore VM"])
        }
        bundle = Bundle(machine: machine, source: source, url: url, timeLimit: timeLimit)
    }

    /// A new context. It evaluates the bundle on its own thread; calls made
    /// before that finishes wait behind it.
    func makeContext() -> NativeContext {
        NativeContext(bundle: bundle)
    }

    /// The ready context (or a new one when none is ready). The next is
    /// prepared a moment later: contexts share one VM and its lock, so
    /// evaluating the bundle now would hold up the render that took this one.
    /// Call on the main thread.
    func takeContext() -> NativeContext {
        let context = ready ?? makeContext()
        ready = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.prepareDelay) { [weak self] in self?.prepare() }
        return context
    }

    static let prepareDelay: TimeInterval = 0.5

    /// Starts evaluating and warming a context in the background, unless one
    /// is ready already.
    func prepare() {
        guard ready == nil else { return }
        let context = makeContext()
        context.warm()
        ready = context
    }

    /// Lets the ready context go, for memory pressure or `warm = "never"`.
    func dropReady() {
        ready = nil
    }

    var hasReadyContext: Bool { ready != nil }
}
