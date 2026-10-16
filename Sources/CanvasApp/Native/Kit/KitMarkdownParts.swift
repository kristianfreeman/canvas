import CanvasCore
import SwiftUI

/// Inline runs in a base style, as one attributed string.
struct MarkdownRuns {
    let style: TextStyle
    let theme: Theme

    static func attributed(_ inlines: [MarkdownInline], style: TextStyle, theme: Theme) -> AttributedString {
        Self(style: style, theme: theme).attributed(inlines)
    }

    func attributed(_ inlines: [MarkdownInline]) -> AttributedString {
        inlines.reduce(into: AttributedString()) { $0 += run($1) }
    }

    func run(_ inline: MarkdownInline) -> AttributedString {
        switch inline {
        case .text(let text, let marks): textRun(text, marks: marks)
        case .code(let text): InlineRuns.chip(text, style: InlineRuns.codeStyle(style), fill: theme.tokens.inlineCodeBg)
        case .link(let href, let inlines): link(href, attributed(inlines))
        case .lineBreak: AttributedString("\n")
        case .footnoteRef(_, let number): footnoteRef(number)
        }
    }

    private func textRun(_ text: String, marks: TextMarks) -> AttributedString {
        var run = AttributedString(text)
        if marks.contains(.bold) || marks.contains(.italic) {
            run.font = style.with {
                if marks.contains(.bold) { $0.weight = .semibold }
                $0.italic = marks.contains(.italic)
            }.font
        }
        if marks.contains(.bold) { run.foregroundColor = Color(theme.tokens.fg) }
        if marks.contains(.strike) { run.strikethroughStyle = .single }
        return run
    }

    private func link(_ href: String, _ content: AttributedString) -> AttributedString {
        var run = content
        if let url = URL(string: href) { run.link = url }
        run.foregroundColor = Color(theme.accent)
        run.underlineStyle = Text.LineStyle(pattern: .solid, color: Color(theme.accent.opacity(0.35)))
        return run
    }

    /// `[n]` raised and smaller, in the accent, as markdown-it-footnote's `sup`.
    private func footnoteRef(_ number: Int) -> AttributedString {
        var run = AttributedString("[\(number)]")
        run.font = style.with { $0.size = (style.size * 0.8).rounded(toPlaces: 2) }.font
        run.baselineOffset = style.size * 0.3
        run.foregroundColor = Color(theme.accent)
        return run
    }
}

/// `blockquote`: a 3 pt accent bar, 1 em indent, softer text.
struct MarkdownQuote: View {
    let blocks: [MarkdownBlock]
    let scope: MarkdownScope
    @Environment(\.kitText) private var style
    @Environment(\.kitTheme) private var theme

    var body: some View {
        MarkdownStack(blocks: blocks, scope: scope)
            .kitText { $0.ink = .soft }
            .padding(.vertical, 0.15 * style.size)
            .padding(.leading, style.size + 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) { Rectangle().fill(Color(theme.accent)).frame(width: 3) }
    }
}

struct MarkdownListView: View {
    let list: MarkdownList
    let depth: Int
    @Environment(\.kitText) private var style

    var body: some View {
        let tasks = list.items.contains(where: \.task)
        VStack(alignment: .leading, spacing: 0.28 * style.size) {
            ForEach(list.items.indices, id: \.self) { index in
                let item = list.items[index]
                if item.task {
                    MarkdownTaskItem(item: item)
                } else {
                    MarkdownListItemView(item: item, marker: marker(index), gutter: (tasks ? 0.2 : 1.45) * style.size)
                }
            }
        }
        .padding(.leading, tasks ? 0.2 * style.size : 0)
        .environment(\.kitListDepth, depth + 1)
    }

    private func marker(_ index: Int) -> String {
        if list.ordered { return "\(list.start + index)." }
        return ["•", "◦", "▪"][min(depth, 2)]
    }
}

/// A plain item: the marker right-aligned in the 1.45 em gutter, then the content.
private struct MarkdownListItemView: View {
    let item: MarkdownListItem
    let marker: String
    let gutter: CGFloat
    @Environment(\.kitText) private var style

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0.45 * style.size) {
            Text(marker)
                .textLayout(style.with {
                    $0.ink = .subtle
                    if marker.hasSuffix(".") { $0.size = (style.size * 0.92).rounded(toPlaces: 2); $0.tabular = true }
                })
                .frame(width: max(0, gutter - 0.25 * style.size), alignment: .trailing)
            MarkdownItemContent(blocks: item.blocks)
        }
    }
}

/// A task item: the 15 pt box with its bottom 2 pt under the baseline, then
/// the content, muted once done.
private struct MarkdownTaskItem: View {
    let item: MarkdownListItem
    @Environment(\.kitText) private var style

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0.6 * style.size) {
            CheckGlyph(checked: item.checked, size: 15, radius: 4, filled: false)
                .alignmentGuide(.firstTextBaseline) { $0.height - 2 }
            MarkdownItemContent(blocks: item.blocks).kitText { if item.checked { $0.ink = .muted } }
        }
    }
}

private struct MarkdownItemContent: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        MarkdownStack(blocks: blocks, scope: .item)
    }
}

struct MarkdownTableView: View {
    let table: MarkdownTable

    var body: some View {
        let count = max(1, table.columnCount)
        let rows = [table.head] + table.rows
        TableLayout(fixed: Array(repeating: nil, count: count)) {
            ForEach(rows.indices, id: \.self) { row in
                ForEach(0..<count, id: \.self) { column in
                    MarkdownTableCell(
                        inlines: column < rows[row].count ? rows[row][column] : [],
                        position: CellPosition(column: column, columns: count, header: row == 0,
                                               lastRow: row > 0 && row == rows.count - 1),
                        align: column < table.align.count ? table.align[column] : nil)
                }
            }
        }
        .kitText { $0.size = MarkdownMetrics.tableSize; $0.tabular = true }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownTableCell: View {
    let inlines: [MarkdownInline]
    let position: CellPosition
    let align: TextAlign?
    @Environment(\.kitText) private var style

    var body: some View {
        TableCellChrome(position: position, align: align) {
            if position.header {
                MarkdownText(inlines: inlines, style: TableCellChrome<EmptyView>.headerStyle(style))
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                MarkdownText(inlines: inlines, style: style)
            }
        }
    }
}

/// The footnotes section: a rule, then a numbered list in 13 pt muted text.
struct MarkdownFootnotes: View {
    let items: [MarkdownFootnote]
    @Environment(\.kitText) private var style
    @Environment(\.kitTheme) private var theme

    var body: some View {
        let size = MarkdownMetrics.footnoteSize
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color(theme.tokens.border)).frame(height: 1).frame(maxWidth: .infinity)
                .padding(.bottom, style.size)
            VStack(alignment: .leading, spacing: 0.28 * size) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 0.45 * size) {
                        Text("\(index + 1).")
                            .textLayout(style.with { $0.size = size * 0.92; $0.tabular = true; $0.ink = .subtle })
                            .frame(width: 0.85 * size, alignment: .trailing)
                        MarkdownStack(blocks: items[index].blocks, scope: .footnote)
                    }
                }
            }
        }
        .kitText { $0.size = size; $0.ink = .muted }
    }
}
