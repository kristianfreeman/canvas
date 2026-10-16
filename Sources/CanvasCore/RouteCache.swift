/// Which renderer draws a panel.
public enum Renderer: String, Sendable {
    case native, web
}

/// Content that needed WebKit, so its next show skips the native attempt.
/// Keyed by path when there is one, else by the source's hash; an entry
/// only matches the source it was recorded for, so an edited file is tried
/// natively again. Least recently used entries go first.
public struct RouteCache {
    public static let defaultCapacity = 64

    public let capacity: Int
    /// Key to source hash, most recently used last.
    private var entries: [(key: String, source: UInt64)] = []

    public init(capacity: Int = defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    /// `.web` when this exact content needed WebKit before, else `.native`.
    public mutating func route(path: String?, source: String) -> Renderer {
        let (key, hash) = Self.key(path: path, source: source)
        guard let index = entries.firstIndex(where: { $0.key == key }), entries[index].source == hash else {
            return .native
        }
        entries.append(entries.remove(at: index))
        return .web
    }

    /// How a native render of this content went: `.web` remembers it, and
    /// `.native` forgets a route recorded for an older version.
    public mutating func record(_ renderer: Renderer, path: String?, source: String) {
        let (key, hash) = Self.key(path: path, source: source)
        entries.removeAll { $0.key == key }
        guard renderer == .web else { return }
        entries.append((key, hash))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    private static func key(path: String?, source: String) -> (String, UInt64) {
        let hash = fnv1a(source)
        guard let path, !path.isEmpty else { return ("source:" + String(hash, radix: 16), hash) }
        return ("path:" + path, hash)
    }

    /// FNV-1a, 64 bit: stable across runs, unlike `Hasher`.
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }
}

/// What an open panel does to show content routed to `wanted`: keep its
/// renderer, or exchange its content for the other kind.
public enum RouteStep: Equatable {
    case stay
    case swap(to: Renderer)

    public static func step(current: Renderer, wanted: Renderer) -> Self {
        current == wanted ? .stay : .swap(to: wanted)
    }
}
