import Foundation

/// Checking and unchecking Markdown task items (`- [ ] text`) in place.
/// A task item's checkbox.
public enum TaskMark: Equatable {
    case open, done
}

public enum TaskList {
    /// Sets the task marker on source line `line` to `checked`. Lines count
    /// from 0 and end at `\r\n`, `\r` or `\n`, as markdown-it counts them,
    /// so the `line` a list item reports names its first line. Nil when that
    /// line isn't a task item; the source unchanged when it already is in
    /// that state.
    public static func setChecked(_ checked: Bool, line: Int, in source: String) -> String? {
        guard let range = lineRange(line, in: source), let mark = markIndex(in: source[range]) else { return nil }
        let current = source[mark]
        guard (current != " ") != checked else { return source }
        var text = source
        text.replaceSubrange(mark...mark, with: checked ? "x" : " ")
        return text
    }

    /// The checkbox on source line `line`, nil when it isn't a task item.
    public static func state(line: Int, in source: String) -> TaskMark? {
        guard let range = lineRange(line, in: source), let mark = markIndex(in: source[range]) else { return nil }
        return source[mark] == " " ? .open : .done
    }

    /// The range of line `index`, without its line ending.
    static func lineRange(_ index: Int, in source: String) -> Range<String.Index>? {
        guard index >= 0 else { return nil }
        var start = source.startIndex
        var remaining = index
        while remaining > 0 {
            guard let end = source[start...].firstIndex(where: \.isLineBreak) else { return nil }
            start = source.index(after: end)
            remaining -= 1
        }
        let end = source[start...].firstIndex(where: \.isLineBreak) ?? source.endIndex
        return start..<end
    }

    /// The index of the character between the brackets of a list item's
    /// leading `[ ]`, `[x]` or `[X]`, which must be followed by a space.
    /// Blockquote markers (`>`) may come first.
    static func markIndex(in line: Substring) -> String.Index? {
        var cursor = line.startIndex
        skipBlanks(line, &cursor)
        while cursor < line.endIndex, line[cursor] == ">" {
            cursor = line.index(after: cursor)
            skipBlanks(line, &cursor)
        }
        guard skipListMarker(line, &cursor), skipBlanks(line, &cursor) > 0 else { return nil }
        let parts = Array(line[cursor...].prefix(4))
        guard parts.count == 4, parts[0] == "[", parts[2] == "]", parts[3] == " " || parts[3] == "\u{a0}",
              parts[1] == " " || parts[1] == "x" || parts[1] == "X" else { return nil }
        return line.index(after: cursor)
    }

    /// `-`, `*`, `+`, or 1 to 9 digits and `.` or `)`.
    private static func skipListMarker(_ line: Substring, _ cursor: inout String.Index) -> Bool {
        guard cursor < line.endIndex else { return false }
        if "-*+".contains(line[cursor]) {
            cursor = line.index(after: cursor)
            return true
        }
        let digits = line[cursor...].prefix { $0.isASCII && $0.isNumber }
        guard (1...9).contains(digits.count) else { return false }
        let after = digits.endIndex
        guard after < line.endIndex, line[after] == "." || line[after] == ")" else { return false }
        cursor = line.index(after: after)
        return true
    }

    @discardableResult
    private static func skipBlanks(_ line: Substring, _ cursor: inout String.Index) -> Int {
        var count = 0
        while cursor < line.endIndex, line[cursor] == " " || line[cursor] == "\t" {
            cursor = line.index(after: cursor)
            count += 1
        }
        return count
    }
}

private extension Character {
    /// `\r\n` is one Character in Swift, so this covers all three endings.
    var isLineBreak: Bool { self == "\n" || self == "\r" || self == "\r\n" }
}
