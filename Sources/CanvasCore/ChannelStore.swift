import Foundation

public enum ChannelOp: String {
    case set, merge
}

/// One `pub`: a value for a channel, how to apply it, and optionally a new
/// history capacity.
public struct ChannelMessage {
    public var channel: String
    public var value: Any
    public var op: ChannelOp
    public var keep: Int?

    public init(channel: String, value: Any, op: ChannelOp = .set, keep: Int? = nil) {
        self.channel = channel
        self.value = value
        self.op = op
        self.keep = keep
    }
}

/// What a subscriber hears after a publish: the latest value, and the
/// values just appended to the history (empty when history is off).
public struct ChannelUpdate {
    public let channel: String
    public let value: Any
    public let appended: [Any]
}

public struct ChannelError: Error, Equatable, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = description }
}

public struct SubscriptionID: Hashable {
    public let channel: String
    let token: Int
}

/// Channels with their latest value and recent history. Not thread-safe;
/// the caller serializes access.
public final class ChannelStore {
    public static let defaultCapacity = 120
    public static let reservedPrefix = "canvas."

    public enum Publisher {
        case external, server
    }

    public typealias Subscriber = (ChannelUpdate) -> Void

    private struct Channel {
        var latest: Any
        var history: History<Any>
    }

    private var channels: [String: Channel] = [:]
    private var subscribers: [String: [Int: Subscriber]] = [:]
    private var nextToken = 0

    public init() {}

    /// Dot-separated segments of `[a-z0-9_-]`.
    public static func isValidName(_ name: String) -> Bool {
        let segments = name.split(separator: ".", omittingEmptySubsequences: false)
        return !segments.isEmpty && segments.allSatisfy(isValidSegment)
    }

    private static func isValidSegment(_ segment: Substring) -> Bool {
        !segment.isEmpty && segment.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "-"
        }
    }

    public static func isReserved(_ name: String) -> Bool {
        name == "canvas" || name.hasPrefix(reservedPrefix)
    }

    /// Whether `publisher` may publish to `channel` with this `keep`.
    public static func validate(_ channel: String, keep: Int? = nil, from publisher: Publisher = .external)
        throws(ChannelError) {
        guard isValidName(channel) else { throw ChannelError("invalid channel name: \(channel)") }
        if publisher == .external, isReserved(channel) {
            throw ChannelError("channel \(channel) is reserved")
        }
        if let keep, keep < 0 { throw ChannelError("keep must be 0 or more") }
    }

    /// Stores the message and notifies the channel's subscribers. Returns the
    /// channel's new latest value.
    @discardableResult
    public func publish(_ message: ChannelMessage, from publisher: Publisher = .external) throws(ChannelError) -> Any {
        try Self.validate(message.channel, keep: message.keep, from: publisher)
        let current = channels[message.channel]
        var channel = current ?? Channel(latest: NSNull(), history: History(capacity: Self.defaultCapacity))
        if let keep = message.keep { channel.history.resize(keep) }
        channel.latest = message.op == .merge
            ? MergePatch.apply(message.value, to: current?.latest)
            : message.value
        channel.history.append(channel.latest)
        channels[message.channel] = channel
        let appended: [Any] = channel.history.capacity > 0 ? [channel.latest] : []
        notify(ChannelUpdate(channel: message.channel, value: channel.latest, appended: appended))
        return channel.latest
    }

    private func notify(_ update: ChannelUpdate) {
        guard let listeners = subscribers[update.channel] else { return }
        for token in listeners.keys.sorted() {
            listeners[token]?(update)
        }
    }

    public func latest(_ channel: String) -> Any? {
        channels[channel]?.latest
    }

    /// Oldest first.
    public func history(_ channel: String) -> [Any] {
        channels[channel]?.history.elements ?? []
    }

    public func capacity(_ channel: String) -> Int? {
        channels[channel]?.history.capacity
    }

    public func subscribe(
        _ channel: String, _ subscriber: @escaping Subscriber
    ) throws(ChannelError) -> SubscriptionID {
        guard Self.isValidName(channel) else { throw ChannelError("invalid channel name: \(channel)") }
        nextToken += 1
        subscribers[channel, default: [:]][nextToken] = subscriber
        return SubscriptionID(channel: channel, token: nextToken)
    }

    public func unsubscribe(_ id: SubscriptionID) {
        subscribers[id.channel]?[id.token] = nil
        if subscribers[id.channel]?.isEmpty == true { subscribers[id.channel] = nil }
    }

    public func subscriberCount(_ channel: String) -> Int {
        subscribers[channel]?.count ?? 0
    }
}
