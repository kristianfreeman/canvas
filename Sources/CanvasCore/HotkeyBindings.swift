import Foundation

/// One panel hotkey: the id it toggles and the show request that draws the
/// panel again once it has closed.
public struct HotkeyBinding {
    public let id: String
    public let hotkey: Hotkey
    /// A show request on the wire, without the fields that belong to one
    /// call (`cmd`, `wait`, `stream`, `focus`, `trace`, `hotkey`).
    public let request: [String: Any]

    static let callFields: Set<String> = ["cmd", "wait", "stream", "focus", "trace", "hotkey", "forget"]

    public init(id: String, hotkey: Hotkey, request: [String: Any]) {
        self.id = id
        self.hotkey = hotkey
        self.request = request.filter { !Self.callFields.contains($0.key) }
    }

    /// The request to show the panel again: the file's current text when it
    /// has a path that can still be read, else the source it was bound with.
    public func showRequest(reading read: (String) -> String? = Self.readFile) -> [String: Any] {
        var json = request
        json["cmd"] = "show"
        json["id"] = id
        json["focus"] = true
        if let path = request["path"] as? String, let text = read(path) { json["source"] = text }
        return json
    }

    public static func readFile(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    var json: [String: Any] { ["id": id, "hotkey": hotkey.description, "request": request] }

    init?(json: Any) {
        guard let object = json as? [String: Any], let id = object["id"] as? String,
              let text = object["hotkey"] as? String, let hotkey = try? Hotkey(parsing: text),
              let request = object["request"] as? [String: Any] else { return nil }
        self.init(id: id, hotkey: hotkey, request: request)
    }
}

/// Panel hotkeys by id, at most one per id and one id per hotkey, saved as
/// `hotkeys.json` in the home directory.
public struct HotkeyBindings {
    public private(set) var byID: [String: HotkeyBinding] = [:]

    public init() {}

    /// The binding for `hotkey`, if an id holds it.
    public func binding(for hotkey: Hotkey) -> HotkeyBinding? {
        byID.values.first { $0.hotkey == hotkey }
    }

    /// Binds `binding.id`, replacing its old hotkey. Another id holding the
    /// same hotkey loses it. Returns the bindings that were replaced or
    /// taken over, whose hotkeys may need unregistering.
    @discardableResult
    public mutating func bind(_ binding: HotkeyBinding) -> [HotkeyBinding] {
        var dropped: [HotkeyBinding] = []
        if let other = self.binding(for: binding.hotkey), other.id != binding.id {
            dropped.append(other)
            byID[other.id] = nil
        }
        if let old = byID[binding.id] { dropped.append(old) }
        byID[binding.id] = binding
        return dropped
    }

    @discardableResult
    public mutating func unbind(_ id: String) -> HotkeyBinding? {
        byID.removeValue(forKey: id)
    }

    /// By id.
    public var sorted: [HotkeyBinding] { byID.values.sorted { $0.id < $1.id } }

    public func encoded() -> Data? {
        JSON.encode(sorted.map(\.json))
    }

    /// Entries that don't decode are dropped; a later entry for the same id
    /// or hotkey wins.
    public init(decoding data: Data) {
        for entry in (JSON.decode(data) as? [Any]) ?? [] {
            if let binding = HotkeyBinding(json: entry) { bind(binding) }
        }
    }

    public static func load(from path: String = Paths.hotkeys) -> Self {
        guard let data = FileManager.default.contents(atPath: path) else { return Self() }
        return Self(decoding: data)
    }

    public func save(to path: String = Paths.hotkeys) {
        guard let data = encoded() else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
