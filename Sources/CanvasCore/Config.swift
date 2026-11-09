import Foundation

/// `~/.config/canvas/config.toml`: flat `key = value` lines, quoted strings,
/// `#` comments. Unknown keys, bad lines and bad values are ignored.
public struct Config: Equatable {
    public enum Warm: String {
        case always, linger, idle, never
    }

    public var warm = Warm.linger
    public var idleMinutes = 10
    public var lingerSeconds = 120
    /// Shows and hides every panel at once, like `canvas toggle --all`.
    public var hotkey: Hotkey?

    public init() {}

    public init(parsing text: String) {
        for line in text.split(whereSeparator: \.isNewline) {
            guard let (key, value) = Self.entry(String(line)) else { continue }
            apply(key, value)
        }
    }

    public static func load(from url: URL = Paths.config) -> Self {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return Self() }
        return Self(parsing: text)
    }

    private enum Value {
        case string(String)
        case bare(String)
    }

    private mutating func apply(_ key: String, _ value: Value) {
        switch value {
        case .string(let raw): applyString(key, raw)
        case .bare(let raw): applyNumber(key, raw)
        }
    }

    private mutating func applyString(_ key: String, _ raw: String) {
        switch key {
        case "warm": warm = Warm(rawValue: raw) ?? warm
        case "hotkey": hotkey = try? Hotkey(parsing: raw)
        default: break
        }
    }

    private mutating func applyNumber(_ key: String, _ raw: String) {
        guard let number = Int(raw) else { return }
        switch key {
        case "idle_minutes" where number > 0: idleMinutes = number
        case "linger_seconds" where number >= 0: lingerSeconds = number
        default: break
        }
    }

    private static func entry(_ line: String) -> (String, Value)? {
        let content = line.prefix { $0 != "#" }
        guard let equals = content.firstIndex(of: "=") else { return nil }
        let key = content[..<equals].trimmingCharacters(in: .whitespaces)
        let raw = content[content.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, let value = value(raw) else { return nil }
        return (key, value)
    }

    private static func value(_ raw: String) -> Value? {
        guard raw.hasPrefix("\"") else { return raw.isEmpty ? nil : .bare(raw) }
        guard raw.count >= 2, raw.hasSuffix("\"") else { return nil }
        let inner = String(raw.dropFirst().dropLast())
        return inner.contains("\"") ? nil : .string(inner)
    }
}
