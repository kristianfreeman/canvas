import Foundation

/// A message the runtime posted through `__post` (docs/native.md, Messages).
enum NativeMessage {
    /// One React commit, in order.
    case ops([[String: Any]])
    case result(Any)
    /// `reason` is "escape" for Esc, which a pinned panel ignores.
    case close(reason: String?)
    /// `every` is in milliseconds, for `canvas.sys.*`.
    case subscribe(channel: String, every: Int?)
    case unsubscribe(channel: String)
    case publish(channel: String, value: Any)
    /// `needsWeb` when a later render used something only WebKit can draw.
    case error(message: String, stack: String?, needsWeb: Bool)
    case open(URL)
    /// Follows the `error` for a timer the time limit stopped: the context
    /// is unusable. Posted by Swift, not the runtime.
    case timedOut(message: String)

    private typealias Parse = ([String: Any]) -> Self?

    private static let parsers: [String: Parse] = [
        "ops": { body in (body["ops"] as? [[String: Any]]).map(Self.ops) },
        "result": { body in .result(body["value"] ?? NSNull()) },
        "close": { body in .close(reason: body["reason"] as? String) },
        "subscribe": { body in
            (body["channel"] as? String).map { .subscribe(channel: $0, every: (body["every"] as? NSNumber)?.intValue) }
        },
        "unsubscribe": { body in (body["channel"] as? String).map { .unsubscribe(channel: $0) } },
        "publish": { body in
            (body["channel"] as? String).map { .publish(channel: $0, value: body["value"] ?? NSNull()) }
        },
        "error": { body in
            .error(
                message: body["message"] as? String ?? "render error",
                stack: body["stack"] as? String,
                needsWeb: (body["needsWeb"] as? NSNumber)?.boolValue ?? false)
        },
        "open": { body in (body["url"] as? String).flatMap(URL.init(string:)).map(Self.open) }
    ]

    init?(_ body: [String: Any]) {
        guard let type = body["type"] as? String, let message = Self.parsers[type]?(body) else { return nil }
        self = message
    }
}

/// What a call into the context returned. Times are `Clock` nanoseconds,
/// taken on the JS thread around the call.
struct NativeResult {
    var error: String?
    var stack: String?
    /// The tree needs the WebKit renderer; no ops were posted for it.
    var needsWeb = false
    /// The call ran over the time limit and was stopped. The context is
    /// unusable afterwards.
    var timedOut = false
    var jsStart: UInt64 = 0
    var jsEnd: UInt64 = 0
    /// What the call returned, as `JSValue.toObject()` gives it.
    var value: Any?

    var ok: Bool { error == nil }

    init(error: String? = nil) {
        self.error = error
    }

    /// From the `{ok} | {error, stack?, needsWeb?}` object the runtime returns.
    init(value: Any?) {
        self.value = value
        guard let object = value as? [String: Any] else { return }
        error = object["error"] as? String
        stack = object["stack"] as? String
        needsWeb = (object["needsWeb"] as? NSNumber)?.boolValue ?? false
    }
}
