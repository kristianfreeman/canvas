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
        switch (key, value) {
        case ("warm", .string(let raw)):
            warm = Warm(rawValue: raw) ?? warm
        case ("idle_minutes", .bare(let raw)):
            if let minutes = Int(raw), minutes > 0 { idleMinutes = minutes }
        case ("linger_seconds", .bare(let raw)):
            if let seconds = Int(raw), seconds >= 0 { lingerSeconds = seconds }
        default:
            break
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
