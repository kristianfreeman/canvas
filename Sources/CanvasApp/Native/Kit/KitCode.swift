import CanvasCore
import SwiftUI

struct CodeBlockView: View {
    @ObservedObject var node: ViewNode

    var body: some View {
        CodeSurface(lines: CodeToken.lines(node.prop("lines")))
    }
}

/// `.cv-codeblock pre`: 12.5 pt mono at 1.62, 13 × 16 padding, radius 10,
/// code background and border. Long lines scroll sideways, as on the web;
/// snapshots clip them.
struct CodeSurface: View {
    static let style = TextStyle(size: 12.5, lineHeight: 1.62, mono: true)

    let lines: [[CodeToken]]
    @Environment(\.kitTheme) private var theme
    @Environment(\.kitControls) private var controls

    var body: some View {
        let code = Text(CodeRuns.attributed(lines, palette: theme.highlight))
            .textLayout(Self.style.with { $0.ink = .custom(theme.highlight.foreground) })
            .fixedSize(horizontal: true, vertical: true)
            .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
        Group {
            if controls == .live {
                ScrollView(.horizontal, showsIndicators: false) { code }
            } else {
                code.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).clipped()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(theme.tokens.codeBg)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(theme.tokens.border), lineWidth: 1))
    }
}

enum CodeRuns {
    /// Lines joined by newlines, each token in its scope's color. Plain
    /// tokens keep the view's foreground.
    static func attributed(_ lines: [[CodeToken]], palette: HighlightPalette) -> AttributedString {
        var result = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { result += AttributedString("\n") }
            for token in line {
                var run = AttributedString(token.text)
                if token.scope != nil { run.foregroundColor = Color(palette.color(token.scope)) }
                if palette.isBold(token.scope) { run.font = CodeSurface.style.with { $0.weight = .bold }.font }
                result += run
            }
        }
        return result
    }
}
