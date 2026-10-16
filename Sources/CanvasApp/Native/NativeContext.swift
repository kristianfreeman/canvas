import Foundation

protocol NativeContextDelegate: AnyObject {
    /// A message the runtime posted, on the main thread, in posting order.
    func nativeContext(_ context: NativeContext, didPost message: NativeMessage)
}

/// One panel's JavaScript context, evaluated and run on its own thread
/// (docs/native.md, Calls). Call from the main thread. Completions and
/// delegate calls arrive on the main thread, and every message a call posts
/// arrives before its completion.
///
/// `reset()` posts no ops, so the panel that reuses the context starts from a
/// new `ViewTree`. A render that returns `needsWeb` posts none either; the
/// next render removes whatever the tree still shows from before.
final class NativeContext {
    weak var delegate: NativeContextDelegate?
    private var core: NativeContextCore?

    init(bundle: NativeRuntime.Bundle) {
        let core = NativeContextCore(bundle: bundle) { [weak self] messages in
            DispatchQueue.main.async {
                guard let self else { return }
                for message in messages { self.delegate?.nativeContext(self, didPost: message) }
            }
        }
        self.core = core
        core.thread.perform { core.load() }
    }

    deinit {
        tearDown()
    }

    /// Whether the script has a `setTimeout` or `setInterval` pending.
    var hasTimers: Bool { core?.thread.hasTimers ?? false }

    /// `payload` is the page payload: `{kind, source, title?, data?, buttons?, wait, theme?, accent?}`.
    func render(_ payload: [String: Any], completion: @escaping (NativeResult) -> Void) {
        call("render", [payload], completion)
    }

    /// Re-renders with new `data`, keeping component state.
    func setData(_ data: Any, completion: ((NativeResult) -> Void)? = nil) {
        call("setData", [data], completion)
    }

    /// Calls a `{"$fn": N}` prop. `onClick` takes no arguments, `onChange`
    /// `[{value}]` or `[{checked}]`, and `onSubmit` `[values]`.
    func invoke(_ function: Int, arguments: [Any] = [], completion: ((NativeResult) -> Void)? = nil) {
        call("invoke", [function, arguments], completion)
    }

    /// Channel delivery: `[{channel, value, history?}]`.
    func push(_ batch: [[String: Any]], completion: ((NativeResult) -> Void)? = nil) {
        call("push", [batch], completion)
    }

    /// Unmounts and clears state and timers so the context can serve another panel.
    func reset(completion: ((NativeResult) -> Void)? = nil) {
        perform({ $0.reset() }, completion)
    }

    /// Runs compile, render and highlighting once without posting anything.
    func warm(completion: ((NativeResult) -> Void)? = nil) {
        call("warm", [], completion)
    }

    /// Runs `js` as a function body in the context (`eval`, tests only).
    func evaluate(_ js: String, completion: @escaping (NativeResult) -> Void) {
        perform({ $0.evaluate(js) }, completion)
    }

    /// Stops the thread and releases the context. Later calls do nothing.
    func tearDown() {
        guard let core else { return }
        self.core = nil
        core.thread.perform { core.close() }
    }

    private func call(_ method: String, _ arguments: [Any], _ completion: ((NativeResult) -> Void)?) {
        perform({ $0.call(method, arguments) }, completion)
    }

    private func perform(
        _ work: @escaping (NativeContextCore) -> NativeResult, _ completion: ((NativeResult) -> Void)?
    ) {
        guard let core else { return }
        core.thread.perform {
            let result = work(core)
            guard let completion else { return }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
