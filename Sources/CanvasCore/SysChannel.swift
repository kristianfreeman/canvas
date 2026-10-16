/// The reserved channels the native sampler feeds.
public enum SysChannel: String, CaseIterable {
    case cpu = "canvas.sys.cpu"
    case memory = "canvas.sys.memory"
    case net = "canvas.sys.net"
    case disk = "canvas.sys.disk"
    case procs = "canvas.sys.procs"
    case battery = "canvas.sys.battery"
    case thermal = "canvas.sys.thermal"

    public static let prefix = "canvas.sys."
    public static let historyCapacity = 300
    /// `canvas.sys.procs` lists this many processes.
    public static let processCount = 40
}

/// Who wants which system channels, and how often. The sampler runs at the
/// smallest interval any subscriber asked for, never faster than `floor`,
/// and not at all without subscribers. Intervals are milliseconds.
public struct SysDemand<Key: Hashable> {
    public static var defaultEvery: Int { 1000 }
    public static var floor: Int { 100 }

    private var requests: [SysChannel: [Key: Int]] = [:]

    public init() {}

    /// A nil `every` asks for the default. Asking again replaces the
    /// subscriber's earlier interval for that channel.
    public mutating func add(_ key: Key, _ channel: SysChannel, every: Int? = nil) {
        requests[channel, default: [:]][key] = every ?? Self.defaultEvery
    }

    public mutating func remove(_ key: Key, _ channel: SysChannel) {
        requests[channel]?[key] = nil
        if requests[channel]?.isEmpty == true { requests[channel] = nil }
    }

    public mutating func removeAll(_ key: Key) {
        for channel in Array(requests.keys) { remove(key, channel) }
    }

    /// The channels with at least one subscriber.
    public var channels: Set<SysChannel> { Set(requests.keys) }

    /// Nil when nothing subscribes, so the sampler stops.
    public var interval: Int? {
        let smallest = requests.values.lazy.flatMap(\.values).min()
        return smallest.map { max($0, Self.floor) }
    }
}
