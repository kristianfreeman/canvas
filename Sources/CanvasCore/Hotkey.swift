import Foundation

public struct HotkeyError: Error, Equatable, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// A global shortcut like `ctrl+opt+t`: modifiers and one key, joined by
/// `+`. Names are case-insensitive. `hyper` is all four modifiers and
/// `meh` is ctrl, opt and shift.
public struct Hotkey: Hashable, CustomStringConvertible, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Self(rawValue: 1)
        public static let option = Self(rawValue: 2)
        public static let shift = Self(rawValue: 4)
        public static let command = Self(rawValue: 8)
        public static let hyper: Self = [.control, .option, .shift, .command]
    }

    /// The key's canonical name, as `description` writes it.
    public let key: String
    /// The macOS virtual key code (`kVK_*`).
    public let keyCode: UInt32
    public let modifiers: Modifiers

    public init(parsing text: String) throws(HotkeyError) {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, !last.isEmpty else { throw HotkeyError("hotkey needs a key, got '\(text)'") }
        var modifiers: Modifiers = []
        for part in parts.dropLast() {
            guard let modifier = Self.modifierNames[part] else {
                throw HotkeyError("unknown modifier '\(part)' in '\(text)'")
            }
            modifiers.formUnion(modifier)
        }
        let name = HotkeyKeys.aliases[last] ?? last
        guard let code = HotkeyKeys.codes[name] else { throw HotkeyError("unknown key '\(last)' in '\(text)'") }
        guard !modifiers.isEmpty || HotkeyKeys.isFunctionKey(name) else {
            throw HotkeyError("hotkey '\(text)' needs a modifier (only F1 to F20 work alone)")
        }
        key = name
        keyCode = code
        self.modifiers = modifiers
    }

    static let modifierNames: [String: Modifiers] = [
        "ctrl": .control, "control": .control, "⌃": .control,
        "opt": .option, "option": .option, "alt": .option, "⌥": .option,
        "shift": .shift, "⇧": .shift,
        "cmd": .command, "command": .command, "⌘": .command,
        "hyper": .hyper, "meh": [.control, .option, .shift]
    ]

    /// Modifiers in the macOS order (ctrl, opt, shift, cmd), then the key.
    public var description: String {
        let names: [(Modifiers, String)] = [(.control, "ctrl"), (.option, "opt"), (.shift, "shift"), (.command, "cmd")]
        return (names.filter { modifiers.contains($0.0) }.map(\.1) + [key]).joined(separator: "+")
    }

    /// Carbon's modifier mask for `RegisterEventHotKey`.
    public var carbonModifiers: UInt32 {
        let masks: [(Modifiers, UInt32)] = [(.command, 0x100), (.shift, 0x200), (.option, 0x800), (.control, 0x1000)]
        return masks.filter { modifiers.contains($0.0) }.reduce(0) { $0 | $1.1 }
    }
}

/// Key names and their ANSI virtual key codes.
enum HotkeyKeys {
    static let aliases: [String: String] = [
        "enter": "return", "esc": "escape", "backspace": "delete", "del": "forwarddelete",
        "pgup": "pageup", "pgdn": "pagedown", "←": "left", "→": "right", "↑": "up", "↓": "down"
    ]

    static func isFunctionKey(_ name: String) -> Bool {
        name.count >= 2 && name.first == "f" && Int(name.dropFirst()).map { (1...20).contains($0) } == true
    }

    static let codes: [String: UInt32] = letters.merging(symbols) { $1 }.merging(named) { $1 }

    private static let letters: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
        "k": 40, "n": 45, "m": 46
    ]

    private static let symbols: [String: UInt32] = [
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "[": 33, "'": 39, ";": 41, "\\": 42, ",": 43, "/": 44, ".": 47, "`": 50
    ]

    private static let named: [String: UInt32] = [
        "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53, "home": 115, "pageup": 116,
        "forwarddelete": 117, "end": 119, "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101,
        "f10": 109, "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64,
        "f18": 79, "f19": 80, "f20": 90
    ]
}
