import Foundation

/// The CSS color syntax native panels accept: hex, `rgb()`/`rgba()`,
/// `hsl()`/`hsla()` (comma or space separated, optional `/ alpha`) and a few
/// named colors. Hue names like `red` are resolved by `Theme` before this.
public enum CSSColor {
    public static func parse(_ text: String) -> RGBA? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("#") { return RGBA(hex: value) }
        if let color = named[value] { return color }
        return function(value)
    }

    static let named: [String: RGBA] = [
        "transparent": .clear, "white": .white, "black": .black,
        "silver": RGBA(red: 0.753, green: 0.753, blue: 0.753), "gray": RGBA(red: 0.502, green: 0.502, blue: 0.502),
        "grey": RGBA(red: 0.502, green: 0.502, blue: 0.502), "navy": RGBA(red: 0, green: 0, blue: 0.502),
        "maroon": RGBA(red: 0.502, green: 0, blue: 0), "olive": RGBA(red: 0.502, green: 0.502, blue: 0),
        "lime": RGBA(red: 0, green: 1, blue: 0), "aqua": RGBA(red: 0, green: 1, blue: 1),
        "cyan": RGBA(red: 0, green: 1, blue: 1), "fuchsia": RGBA(red: 1, green: 0, blue: 1),
        "magenta": RGBA(red: 1, green: 0, blue: 1)
    ]

    private static func function(_ value: String) -> RGBA? {
        guard let open = value.firstIndex(of: "("), value.hasSuffix(")") else { return nil }
        let name = value[..<open].trimmingCharacters(in: .whitespaces)
        let inner = value[value.index(after: open)..<value.index(before: value.endIndex)]
        guard let parts = components(inner) else { return nil }
        switch name {
        case "rgb", "rgba": return rgb(parts)
        case "hsl", "hsla": return hsl(parts)
        default: return nil
        }
    }

    /// `1, 2, 3[, a]` or `1 2 3[ / a]` as three or four strings.
    private static func components(_ inner: Substring) -> [String]? {
        let parts: [String]
        if inner.contains(",") {
            parts = inner.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            let halves = inner.split(separator: "/", omittingEmptySubsequences: false)
            guard halves.count <= 2 else { return nil }
            parts = halves[0].split(whereSeparator: \.isWhitespace).map(String.init)
                + halves.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return (3...4).contains(parts.count) && !parts.contains(where: \.isEmpty) ? parts : nil
    }

    private static func rgb(_ parts: [String]) -> RGBA? {
        let channels = parts.prefix(3).map { amount($0, scale: 255) }
        guard let red = channels[0], let green = channels[1], let blue = channels[2],
              let alpha = parts.count == 4 ? amount(parts[3], scale: 1) : 1 else { return nil }
        return RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func hsl(_ parts: [String]) -> RGBA? {
        let hueText = parts[0].hasSuffix("deg") ? String(parts[0].dropLast(3)) : parts[0]
        guard let hue = number(hueText), parts[1].hasSuffix("%"), parts[2].hasSuffix("%"),
              let saturation = amount(parts[1], scale: 1), let lightness = amount(parts[2], scale: 1),
              let alpha = parts.count == 4 ? amount(parts[3], scale: 1) : 1 else { return nil }
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        func channel(_ offset: Double) -> Double {
            let turn = (offset + hue / 30).truncatingRemainder(dividingBy: 12)
            let wrapped = turn < 0 ? turn + 12 : turn
            return lightness - chroma / 2 * max(-1, min(wrapped - 3, 9 - wrapped, 1))
        }
        return RGBA(red: channel(0), green: channel(8), blue: channel(4), alpha: alpha)
    }

    /// A plain number divided by `scale`, or a percentage of 1.
    private static func amount(_ text: String, scale: Double) -> Double? {
        if text.hasSuffix("%") { return number(String(text.dropLast())).map { $0 / 100 } }
        return number(text).map { $0 / scale }
    }

    private static func number(_ text: String) -> Double? {
        guard let first = text.first, first.isNumber || first == "." || first == "-" || first == "+",
              let value = Double(text), value.isFinite else { return nil }
        return value
    }
}
