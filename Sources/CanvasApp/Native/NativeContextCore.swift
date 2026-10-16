import CanvasCore
import Foundation
import JavaScriptCore

/// The JS-thread half of a `NativeContext`: the `JSContext`, its globals and
/// its timers. Everything except `init` runs on `thread`.
final class NativeContextCore {
    let thread: JSThread
    private let bundle: NativeRuntime.Bundle
    /// Messages posted together, delivered in order in one main-thread turn.
    private let onMessages: ([NativeMessage]) -> Void
    private var context: JSContext?
    private var api: JavaScriptCore.JSValue?
    private var fireTimer: JavaScriptCore.JSValue?
    /// Why calls fail without running: the bundle didn't load, or a call was
    /// stopped by the time limit and left the runtime mid-render.
    private var unusable: String?
    private var watchdog: NativeContextWatchdog?

    init(bundle: NativeRuntime.Bundle, onMessages: @escaping ([NativeMessage]) -> Void) {
        self.bundle = bundle
        self.onMessages = onMessages
        thread = JSThread(name: "canvas.js")
        if !NativeTimeLimit.isAvailable {
            watchdog = NativeContextWatchdog(limit: bundle.timeLimit) {
                onMessages([.error(message: "The panel's script stopped responding.", stack: nil, needsWeb: false)])
            }
        }
    }

    func load() {
        guard let context = JSContext(virtualMachine: bundle.machine) else {
            unusable = "could not create a JavaScript context"
            return
        }
        context.name = "Canvas native"
        thread.onTimer = { [weak self] id in self?.timerFired(id) }
        NativeTimeLimit.install(on: JSContextGetGroup(context.jsGlobalContextRef), seconds: bundle.timeLimit)
        installGlobals(in: context)
        context.evaluateScript(NativeContextPrelude.source)
        context.evaluateScript(bundle.source, withSourceURL: bundle.url)
        self.context = context
        if let exception = context.exception {
            unusable = "native runtime failed to load: \(exception)"
            return
        }
        api = context.objectForKeyedSubscript("canvasNative")
        fireTimer = context.objectForKeyedSubscript("__fireTimer")
        if api?.isObject != true { unusable = "native.js did not define canvasNative" }
    }

    /// Calls `canvasNative[method](...arguments)`.
    func call(_ method: String, _ arguments: [Any]) -> NativeResult {
        guard let api else { return NativeResult(error: unusable ?? "native runtime not loaded") }
        return run { api.invokeMethod(method, withArguments: arguments) }
    }

    /// Unmounts, clears runtime state and cancels every timer.
    func reset() -> NativeResult {
        let result = call("reset", [])
        _ = context?.objectForKeyedSubscript("__resetTimers")?.call(withArguments: [])
        thread.cancelAllTimers()
        return result
    }

    func close() {
        thread.cancelAllTimers()
        api = nil
        fireTimer = nil
        context = nil
        thread.stop()
    }

    private func run(_ body: () -> JavaScriptCore.JSValue?) -> NativeResult {
        if let unusable { return NativeResult(error: unusable) }
        guard let context else { return NativeResult(error: "native runtime not loaded") }
        context.exception = nil
        watchdog?.begin()
        let start = Clock.now()
        let value = body()
        let end = Clock.now()
        watchdog?.end()
        var result = outcome(of: value, in: context)
        result.jsStart = start
        result.jsEnd = end
        return result
    }

    private func outcome(of value: JavaScriptCore.JSValue?, in context: JSContext) -> NativeResult {
        if NativeTimeLimit.takeTermination(of: context.jsGlobalContextRef) {
            let message = "The panel's script ran longer than \(Self.seconds(bundle.timeLimit)) and was stopped."
            unusable = message
            var result = NativeResult(error: message)
            result.timedOut = true
            return result
        }
        if let exception = context.exception {
            context.exception = nil
            var result = NativeResult(error: exception.toString() ?? "JavaScript error")
            result.stack = exception.objectForKeyedSubscript("stack")?.toString()
            return result
        }
        return NativeResult(value: value?.toObject())
    }

    /// Evaluates `js` as a function body and returns its value.
    func evaluate(_ js: String) -> NativeResult {
        guard let context else { return NativeResult(error: unusable ?? "native runtime not loaded") }
        return run { context.evaluateScript("(function () {\n\(js)\n})()") }
    }

    private func timerFired(_ id: Int) {
        guard let fireTimer else { return }
        let result = run { fireTimer.call(withArguments: [id]) }
        guard let error = result.error else { return }
        let reported = NativeMessage.error(message: error, stack: result.stack, needsWeb: false)
        onMessages(result.timedOut ? [reported, .timedOut(message: error)] : [reported])
    }

    private static func seconds(_ value: TimeInterval) -> String {
        value == value.rounded() ? "\(Int(value)) s" : String(format: "%.1f s", value)
    }
}

extension NativeContextCore {
    private func installGlobals(in context: JSContext) {
        let post: @convention(block) (JavaScriptCore.JSValue?) -> Void = { [weak self] value in
            guard let body = value?.toObject() as? [String: Any], let message = NativeMessage(body) else { return }
            self?.onMessages([message])
        }
        let schedule: @convention(block) (Int, Double, Bool) -> Void = { [weak self] id, milliseconds, repeats in
            self?.thread.schedule(id, after: milliseconds / 1000, repeats: repeats)
        }
        let cancel: @convention(block) (Int) -> Void = { [weak self] id in self?.thread.cancelTimer(id) }
        let now: @convention(block) () -> Double = { Double(Clock.now()) / 1_000_000 }
        let log: @convention(block) (String, String) -> Void = { level, text in debugLog("[native \(level)] \(text)") }
        let globals: [String: Any] = [
            "__post": post, "__schedule": schedule, "__cancel": cancel, "__now": now, "__log": log
        ]
        for (name, function) in globals {
            context.setObject(function, forKeyedSubscript: name as NSString)
        }
    }
}
