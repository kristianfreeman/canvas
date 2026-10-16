/// Latest-wins throttle for a stream of values: at most one flush per
/// `interval`, and a flush always delivers the newest value offered.
/// Times are `Clock` nanoseconds.
public struct DataCoalescer<Value> {
    /// One display frame at 60 Hz.
    public static var frameInterval: UInt64 { 16_666_667 }

    public let interval: UInt64
    private var pending: Value?
    private var scheduled = false
    private var lastFlush: UInt64?

    public init(interval: UInt64 = Self.frameInterval) {
        self.interval = interval
    }

    public var hasPending: Bool { pending != nil }

    /// Stores `value`. Returns the delay in nanoseconds after which the
    /// caller should call `flush`, or nil when a flush is already scheduled.
    public mutating func offer(_ value: Value, now: UInt64) -> UInt64? {
        pending = value
        guard !scheduled else { return nil }
        scheduled = true
        guard let lastFlush, now &- lastFlush < interval else { return 0 }
        return interval - (now &- lastFlush)
    }

    /// The newest value since the last flush, if any.
    public mutating func flush(now: UInt64) -> Value? {
        scheduled = false
        guard let value = pending else { return nil }
        pending = nil
        lastFlush = now
        return value
    }
}
