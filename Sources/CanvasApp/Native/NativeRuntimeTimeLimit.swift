import Darwin
import Foundation
import JavaScriptCore

/// The per-call execution limit. `JSContextGroupSetExecutionTimeLimit` is
/// exported by JavaScriptCore but not in its public headers, so it is looked
/// up at run time. Without it, callers fall back to a watchdog that can only
/// report a hung context.
enum NativeTimeLimit {
    private typealias ShouldTerminate = @convention(c) (JSContextRef?, UnsafeMutableRawPointer?) -> Bool
    private typealias SetLimit = @convention(c) (JSContextGroupRef?, Double, ShouldTerminate?, UnsafeMutableRawPointer?)
        -> Void

    private static let setLimit: SetLimit? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "JSContextGroupSetExecutionTimeLimit") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetLimit.self)
    }()

    private static let lock = NSLock()
    private static var terminated: Set<JSGlobalContextRef> = []

    private static let shouldTerminate: ShouldTerminate = { context, _ in
        guard let context, let global = JSContextGetGlobalContext(context) else { return true }
        lock.lock()
        terminated.insert(global)
        lock.unlock()
        return true
    }

    static var isAvailable: Bool { setLimit != nil }

    /// Limits every call into contexts of `group` to `seconds`. Returns false
    /// when the function isn't available.
    @discardableResult
    static func install(on group: JSContextGroupRef?, seconds: TimeInterval) -> Bool {
        guard let setLimit else { return false }
        setLimit(group, seconds, shouldTerminate, nil)
        return true
    }

    /// Whether the limit stopped a call in `context` since the last check.
    static func takeTermination(of context: JSGlobalContextRef) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminated.remove(context) != nil
    }
}
