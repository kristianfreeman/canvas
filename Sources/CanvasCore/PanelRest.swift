import Foundation

/// A closed panel can wait hidden, fully drawn, for the same request again,
/// which then shows it without rendering. These rules say which panels may
/// rest and which request counts as the same.
public enum PanelRest {
    /// How many closed panels wait at once.
    public static let capacity = 3

    /// A `--wait` panel holds the last caller's form state, and a stream's
    /// data came from a connection that has ended.
    public static func mayRest(_ request: ShowRequest) -> Bool {
        !request.wait && !request.stream
    }

    /// Everything that changes what the panel draws or where it goes.
    public static func sameShow(_ resting: ShowRequest, _ new: ShowRequest) -> Bool {
        mayRest(new)
            && resting.kind == new.kind
            && resting.source == new.source
            && resting.path == new.path
            && resting.title == new.title
            && resting.buttons == new.buttons
            && resting.accent == new.accent
            && resting.theme == new.theme
            && resting.placement == new.placement
            && JSONValue(resting.data) == JSONValue(new.data)
    }
}

/// Resting values by id, at most `capacity`, the longest resting first out.
public struct RestShelf<Value> {
    public let capacity: Int
    private var entries: [(id: String, value: Value)] = []

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
    }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    /// Rests `value` under `id` and returns what that pushed out: an older
    /// value under the same id, then the longest resting past `capacity`.
    public mutating func put(_ id: String, _ value: Value) -> [Value] {
        var out = take(id).map { [$0] } ?? []
        entries.append((id, value))
        while entries.count > capacity {
            out.append(entries.removeFirst().value)
        }
        return out
    }

    public mutating func take(_ id: String) -> Value? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: index).value
    }

    public mutating func removeAll() -> [Value] {
        defer { entries.removeAll() }
        return entries.map(\.value)
    }
}
