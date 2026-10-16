import AppKit
import CanvasCore
import SwiftUI

/// A text color by token, so it follows theme changes.
enum Ink: Equatable {
    case fg, soft, muted, subtle, accent
    case custom(RGBA)

    func color(_ theme: Theme) -> RGBA {
        switch self {
        case .fg: theme.tokens.fg
        case .soft: theme.tokens.fgSoft
        case .muted: theme.tokens.fgMuted
        case .subtle: theme.tokens.fgSubtle
        case .accent: theme.accent
        case .custom(let rgba): rgba
        }
    }
}

/// The inherited text properties of the web kit's CSS: size in points,
/// line height as a multiple, tracking in em.
struct TextStyle: Equatable {
    var size: CGFloat = 14
    var weight: Font.Weight = .regular
    var ink = Ink.fg
    var lineHeight: CGFloat = 1.55
    var mono = false
    var tracking: CGFloat = 0
    var uppercase = false
    var tabular = false
    var italic = false

    static let body = Self()

    var font: Font {
        var font = Font.custom(mono ? KitFont.mono : KitFont.ui, fixedSize: size).weight(weight)
        if tabular { font = font.monospacedDigit() }
        return italic ? font.italic() : font
    }

    /// Extra space between lines so a line box is `lineHeight × size`, as in CSS.
    var leading: CGFloat {
        max(0, size * lineHeight - KitFont.naturalLineHeight(mono: mono, size: size))
    }

    func with(_ change: (inout Self) -> Void) -> Self {
        var copy = self
        change(&copy)
        return copy
    }
}

enum KitFont {
    static let ui = "Geist"
    static let mono = "Berkeley Mono"

    nonisolated(unsafe) private static var lineHeights: [String: CGFloat] = [:]

    /// The font's own line height (ascent + descent + leading), which SwiftUI uses per line.
    static func naturalLineHeight(mono: Bool, size: CGFloat) -> CGFloat {
        let key = "\(mono):\(size)"
        if let cached = lineHeights[key] { return cached }
        let font = NSFont(name: mono ? Self.mono : ui, size: size) ?? .systemFont(ofSize: size)
        let height = font.ascender - font.descender + font.leading
        lineHeights[key] = height
        return height
    }

    /// `weight` as the kit takes it: a CSS number or `normal`, `medium`, `semibold`, `bold`.
    static func weight(_ value: JSONValue?) -> Font.Weight? {
        if let name = value?.string { return names[name] }
        guard let number = value?.number else { return nil }
        return numbers.min { abs($0.key - number) < abs($1.key - number) }?.value
    }

    private static let names: [String: Font.Weight] = [
        "normal": .regular, "medium": .medium, "semibold": .semibold, "bold": .bold
    ]

    private static let numbers: [Double: Font.Weight] = [
        100: .ultraLight, 200: .thin, 300: .light, 400: .regular, 500: .medium, 600: .semibold, 700: .bold,
        800: .heavy, 900: .black
    ]
}

extension Text {
    /// Font, color and tracking as `Text` modifiers, which add no views.
    func styled(_ style: TextStyle, theme: Theme) -> Text {
        let text = font(style.font).foregroundColor(Color(style.ink.color(theme)))
        return style.tracking == 0 ? text : text.tracking(style.tracking * style.size)
    }
}

/// CSS half-leading above and below, and the extra space between lines.
struct LineBox: ViewModifier {
    let leading: CGFloat

    func body(content: Content) -> some View {
        content.lineSpacing(leading).padding(.vertical, leading / 2)
    }
}

/// Draws text in a `TextStyle`, with CSS half-leading above and below.
struct TextLayout: ViewModifier {
    let style: TextStyle
    @Environment(\.kitTheme) private var theme

    func body(content: Content) -> some View {
        let leading = style.leading
        return content
            .font(style.font)
            .foregroundColor(Color(style.ink.color(theme)))
            .tracking(style.tracking * style.size)
            .textCase(style.uppercase ? .uppercase : nil)
            .lineSpacing(leading)
            .padding(.vertical, leading / 2)
    }
}

extension View {
    func textLayout(_ style: TextStyle) -> some View { modifier(TextLayout(style: style)) }
}
