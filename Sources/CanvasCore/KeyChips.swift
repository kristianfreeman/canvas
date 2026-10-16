import Foundation

/// One chip of a shortcut, as examples/keys.tsx draws it.
public enum KeyChip: Equatable {
    case key(String)
    /// The accent ✦ Hyper chip.
    case hyper
    /// A word like `tap` or `then`, drawn as quiet text.
    case note(String)
    /// `→` between two non-arrow keys: a sequence separator.
    case then
    case plus
}

/// Parses a `keys` prop into chips, with the rules of examples/keys.tsx.
public enum KeyChips {
    public static let multiWord = ["Caps Lock", "Page Up", "Page Down", "Num Lock"]
    public static let notes: Set<String> = ["tap", "hold", "twice", "double", "then", "or", "again"]
    public static let arrows: Set<String> = ["←", "↑", "↓", "→"]

    /// A string is split on whitespace; an array is taken as the tokens.
    public static func parse(_ keys: JSONValue?) -> [KeyChip] {
        switch keys {
        case .string(let text): parse(tokens: tokenize(text))
        case .array(let items): parse(tokens: items.compactMap(\.string))
        default: []
        }
    }

    public static func parse(_ keys: String) -> [KeyChip] { parse(tokens: tokenize(keys)) }

    public static func parse(tokens: [String]) -> [KeyChip] {
        tokens.indices.map { index in
            let token = tokens[index]
            let previous = index > 0 ? tokens[index - 1] : nil
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil
            if isSeparator(token, previous: previous, next: next) { return .then }
            if token == "+" { return .plus }
            if notes.contains(token.lowercased()) { return .note(token) }
            return token.lowercased() == "hyper" ? .hyper : .key(token)
        }
    }

    /// Whitespace-separated words, with two-word keys like `Caps Lock` kept together.
    public static func tokenize(_ keys: String) -> [String] {
        let words = keys.split(whereSeparator: \.isWhitespace).map(String.init)
        var tokens: [String] = []
        var index = 0
        while index < words.count {
            let pair = index + 1 < words.count ? "\(words[index]) \(words[index + 1])".lowercased() : ""
            if let multi = multiWord.first(where: { $0.lowercased() == pair }) {
                tokens.append(multi)
                index += 2
            } else {
                tokens.append(words[index])
                index += 1
            }
        }
        return tokens
    }

    static func isSeparator(_ token: String, previous: String?, next: String?) -> Bool {
        guard token == "→", let previous, let next else { return false }
        return !arrows.contains(previous) && !arrows.contains(next)
    }
}
