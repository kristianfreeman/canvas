/// Channel messages waiting for a page's next `canvas.push`. Per channel the
/// latest value wins and history appends accumulate, oldest first.
public struct PushBatch {
    private struct Entry {
        var value: Any
        /// Nil leaves `history` out, so the page appends `value` itself.
        var history: [Any]?
    }

    private var order: [String] = []
    private var entries: [String: Entry] = [:]

    public init() {}

    public var isEmpty: Bool { order.isEmpty }

    /// The first push of a subscription: the whole buffered history,
    /// replacing anything already queued for the channel.
    public mutating func replace(_ channel: String, value: Any, history: [Any]) {
        if entries[channel] == nil { order.append(channel) }
        entries[channel] = Entry(value: value, history: history.isEmpty ? nil : history)
    }

    /// A publish since the last push. `limit` caps the queued history, so a
    /// page that falls behind loses the oldest values, never the latest.
    public mutating func add(_ update: ChannelUpdate, limit: Int) {
        guard var entry = entries[update.channel] else {
            order.append(update.channel)
            entries[update.channel] = Entry(value: update.value, history: Self.capped(update.appended, limit))
            return
        }
        entry.value = update.value
        if entry.history != nil || !update.appended.isEmpty {
            entry.history = Self.capped((entry.history ?? []) + update.appended, limit)
        }
        entries[update.channel] = entry
    }

    public mutating func remove(_ channel: String) {
        guard entries.removeValue(forKey: channel) != nil else { return }
        order.removeAll { $0 == channel }
    }

    /// The `canvas.push` argument, channels in the order first queued.
    public mutating func take() -> [[String: Any]] {
        let batch = order.compactMap { channel -> [String: Any]? in
            guard let entry = entries[channel] else { return nil }
            var message: [String: Any] = ["channel": channel, "value": entry.value]
            if let history = entry.history { message["history"] = history }
            return message
        }
        order.removeAll(keepingCapacity: true)
        entries.removeAll(keepingCapacity: true)
        return batch
    }

    private static func capped(_ values: [Any], _ limit: Int) -> [Any]? {
        guard !values.isEmpty else { return nil }
        return values.count > limit ? Array(values.suffix(max(limit, 1))) : values
    }
}
