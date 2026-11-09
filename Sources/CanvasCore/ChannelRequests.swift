import Foundation

/// A `pub` request: `{channel, value, op, keep}`, or with `"stream":true`
/// a value per following line.
public struct PubRequest {
    public let channel: String
    public let op: ChannelOp
    public let keep: Int?
    public let stream: Bool
    public let persist: Bool
    public let value: Any?

    public init(_ json: [String: Any]) throws(ChannelError) {
        guard let channel = json["channel"] as? String else { throw ChannelError("pub needs a channel") }
        guard let op = ChannelOp(rawValue: json["op"] as? String ?? ChannelOp.set.rawValue) else {
            throw ChannelError("op must be set, merge or clear")
        }
        let keep = try Self.keep(json["keep"])
        try ChannelStore.validate(channel, keep: keep)
        stream = json["stream"] as? Bool ?? false
        persist = json["persist"] as? Bool ?? false
        value = json["value"]
        if op == .clear, stream || value != nil { throw ChannelError("clear takes no value") }
        if !stream, value == nil, op != .clear { throw ChannelError("pub needs a value") }
        self.channel = channel
        self.op = op
        self.keep = keep
    }

    private static func keep(_ raw: Any?) throws(ChannelError) -> Int? {
        guard let raw, !(raw is NSNull) else { return nil }
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFNumberGetTypeID(),
              let keep = Int(exactly: number.doubleValue) else {
            throw ChannelError("keep must be a whole number")
        }
        return keep
    }

    /// The message for `value`. A stream resizes the history once, with its
    /// first value.
    public func message(_ value: Any, first: Bool = true) -> ChannelMessage {
        ChannelMessage(channel: channel, value: value, op: op, keep: first ? keep : nil, persist: persist)
    }
}

/// A `sub` request: `{channels: [...], history}`.
public struct SubRequest {
    /// Valid names, duplicates dropped, in the order given.
    public let channels: [String]
    public let history: Bool

    public init(_ json: [String: Any]) throws(ChannelError) {
        guard let names = json["channels"] as? [Any], !names.isEmpty else {
            throw ChannelError("sub needs at least one channel")
        }
        var channels: [String] = []
        for name in names {
            guard let name = name as? String, ChannelStore.isValidName(name) else {
                throw ChannelError("invalid channel name: \(name)")
            }
            if !channels.contains(name) { channels.append(name) }
        }
        self.channels = channels
        history = json["history"] as? Bool ?? false
    }

    /// The `history` events to send before any live message: one per
    /// channel with buffered values, in request order, values oldest first.
    public func replay(from store: ChannelStore) -> [[String: Any]] {
        guard history else { return [] }
        return channels.compactMap { channel in
            let values = store.history(channel)
            return values.isEmpty ? nil : ["event": "history", "channel": channel, "values": values]
        }
    }
}
