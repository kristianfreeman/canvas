import CanvasCore
import SwiftUI

struct HeadingView: View {
    @ObservedObject var node: ViewNode

    var body: some View {
        let level = min(max(KitValue.int(node.prop("level"), 2), 1), 4)
        BlockFlow(nodes: node.children).kitText { $0 = Self.style(level) }
    }

    static func style(_ level: Int) -> TextStyle {
        var style = TextStyle(size: [22, 17, 14.5, 11.5][level - 1], weight: .semibold, lineHeight: 1.3,
                              tracking: level == 1 ? -0.018 : -0.012)
        if level == 4 {
            style.uppercase = true
            style.tracking = 0.08
            style.ink = .muted
        }
        return style
    }
}

struct TextView: View {
    @ObservedObject var node: ViewNode
    @Environment(\.kitTheme) private var theme
    @Environment(\.kitText) private var inherited

    var body: some View {
        BlockFlow(nodes: node.children).environment(\.kitText, inherited.with(Self.style(node.props, theme: theme)))
    }

    static let sizes: [String: (size: CGFloat, lineHeight: CGFloat)] = [
        "sm": (12.5, 1.5), "md": (14, 1.55), "lg": (16, 1.5)
    ]

    static func style(_ props: [String: JSONValue], theme: Theme) -> (inout TextStyle) -> Void {
        let size = sizes[props["size"]?.string ?? "md"] ?? (14, 1.55)
        let weight = KitFont.weight(props["weight"])
        let color = props["color"]?.string.map { theme.resolve($0) }
        let muted = props["muted"]?.isTrue == true
        let mono = props["mono"]?.isTrue == true
        return { style in
            style.size = mono ? (size.size * 0.92).rounded(toPlaces: 2) : size.size
            style.lineHeight = size.lineHeight
            style.mono = mono
            if let weight { style.weight = weight }
            if muted { style.ink = .muted }
            if let color { style.ink = .custom(color) }
        }
    }
}

/// `Code` as a flex item: an inline code chip on its own.
struct CodeView: View {
    @ObservedObject var node: ViewNode
    @Environment(\.kitText) private var inherited
    @Environment(\.kitTheme) private var theme

    var body: some View {
        let style = InlineRuns.codeStyle(inherited).with { $0.ink = .fg; $0.lineHeight = 1.3 }
        Text(node.textContent)
            .textLayout(style)
            .padding(.horizontal, style.size * 0.4)
            .padding(.vertical, style.size * 0.15)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(theme.tokens.inlineCodeBg)))
    }
}

struct KbdView: View {
    @ObservedObject var node: ViewNode

    var body: some View {
        KbdChip(label: node.textContent, accent: node.prop("tone")?.string == "accent")
    }
}

/// A key cap: 22 pt tall, 1 pt border with a 2 pt bottom edge.
struct KbdChip: View {
    let label: String
    var accent = false
    var size: CGFloat = 11.5
    @Environment(\.kitTheme) private var theme

    var body: some View {
        let colors = KbdColors(theme: theme, accent: accent)
        Text(label)
            .font(.custom(KitFont.mono, fixedSize: size).weight(.medium))
            .foregroundColor(Color(colors.text))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 19)
            .padding(.top, 1)
            .padding(.bottom, 2)
            .background(KbdCap(colors: colors))
    }
}

struct KbdColors {
    let text, fill, border, edge: RGBA

    init(theme: Theme, accent: Bool) {
        let tokens = theme.tokens
        guard accent else {
            (text, fill, border, edge) = (tokens.fg, tokens.kbdBg, tokens.kbdBorder, tokens.kbdEdge)
            return
        }
        text = theme.accent
        fill = theme.accent.mixed(0.07, with: tokens.kbdBg)
        border = theme.accent.mixed(0.3, with: tokens.kbdBorder)
        edge = theme.accent.mixed(0.38, with: tokens.kbdEdge)
    }
}

private struct KbdCap: View {
    let colors: KbdColors

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color(colors.fill))
                .padding(EdgeInsets(top: 1, leading: 1, bottom: 2, trailing: 1))
            RoundedRectangle(cornerRadius: 5).strokeBorder(Color(colors.border), lineWidth: 1)
                .mask { VStack(spacing: 0) { Rectangle(); Color.clear.frame(height: 2) } }
            RoundedRectangle(cornerRadius: 5).fill(Color(colors.edge))
                .mask { VStack(spacing: 0) { Color.clear; Rectangle().frame(height: 2) } }
        }
    }
}

struct KeyChipsView: View {
    @ObservedObject var node: ViewNode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(KeyChips.parse(node.prop("keys")).enumerated()), id: \.offset) { _, chip in
                KeyChipView(chip: chip)
            }
        }
        .frame(minHeight: 31)
    }
}

private struct KeyChipView: View {
    let chip: KeyChip

    var body: some View {
        switch chip {
        case .then: quiet("→", size: 12).padding(.horizontal, 3)
        case .plus: quiet("+", size: 12).padding(.horizontal, 3)
        case .note(let text): quiet(text, size: 12.5).padding(.leading, 3)
        case .hyper: KbdChip(label: "✦", accent: true, size: 12.5)
        case .key(let text): KbdChip(label: text, size: KeyChips.arrows.contains(text) ? 13 : 11.5)
        }
    }

    private func quiet(_ text: String, size: CGFloat) -> some View {
        Text(text).textLayout(TextStyle(size: size, ink: .subtle, lineHeight: 1.2)).fixedSize()
    }
}
