import CanvasCore
import SwiftUI

/// Where a block sits, which sets its margins (styles.css `.cv-prose`).
enum MarkdownScope {
    case prose
    /// Inside a list item. Item paragraphs are tight: blocks carry no
    /// loose/tight flag, and tight lists are the common case.
    case item
    case footnote
}

private struct ListDepthKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// How many lists deep a Markdown block is, for nested bullet shapes.
    var kitListDepth: Int {
        get { self[ListDepthKey.self] }
        set { self[ListDepthKey.self] = newValue }
    }
}

struct BlockMargins: Equatable {
    let top: CGFloat
    let bottom: CGFloat

    init(_ top: CGFloat, _ bottom: CGFloat) {
        self.top = top
        self.bottom = bottom
    }

    init(both: CGFloat) { self.init(both, both) }
}

enum MarkdownMetrics {
    static let prose = TextStyle(size: 14.5, lineHeight: 1.65)
    static let footnoteSize: CGFloat = 13
    static let tableSize: CGFloat = 13.5

    /// `.cv-prose h1`–`h6`.
    static func heading(_ level: Int) -> TextStyle {
        let sizes: [CGFloat] = [23, 18, 15.5, 14.5, 12, 12]
        var style = TextStyle(size: sizes[min(max(level, 1), 6) - 1], weight: .semibold, lineHeight: 1.3,
                              tracking: level == 1 ? -0.018 : -0.011)
        if level >= 5 {
            style.uppercase = true
            style.tracking = 0.07
            style.ink = .muted
        }
        return style
    }

    /// Margins in points for a block whose text is `size` points.
    static func margins(_ block: MarkdownBlock, scope: MarkdownScope, size: CGFloat) -> BlockMargins {
        switch block {
        case .heading(let level, _):
            let em = heading(level).size
            return BlockMargins(level == 1 ? 0.2 * em : 1.7 * em, 0.55 * em)
        case .paragraph: return BlockMargins(both: [.prose: 0.7, .item: 0, .footnote: 0.2][scope, default: 0.7] * size)
        case .list: return BlockMargins(both: (scope == .item ? 0.25 : 0.7) * size)
        case .quote: return BlockMargins(both: 1.1 * size)
        case .code: return BlockMargins(both: size)
        default: return leafMargins(block, size: size)
        }
    }

    private static func leafMargins(_ block: MarkdownBlock, size: CGFloat) -> BlockMargins {
        switch block {
        case .table: BlockMargins(both: 1.1 * tableSize)
        case .rule: BlockMargins(both: 2 * size)
        case .footnotes: BlockMargins(2.2 * size, 0)
        default: BlockMargins(both: 0)
        }
    }

    /// The space above each block: adjacent margins collapse to the larger,
    /// and the first block's top margin is dropped, as in CSS.
    static func gaps(_ margins: [BlockMargins]) -> [CGFloat] {
        margins.indices.map { index in index == 0 ? 0 : max(margins[index - 1].bottom, margins[index].top) }
    }
}

struct MarkdownView: View {
    @ObservedObject var node: ViewNode

    var body: some View {
        MarkdownStack(blocks: MarkdownBlocks.decode(node.prop("blocks")), scope: .prose)
            .kitText { $0.size = MarkdownMetrics.prose.size; $0.lineHeight = MarkdownMetrics.prose.lineHeight }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Blocks top to bottom with collapsed margins between them.
struct MarkdownStack: View {
    let blocks: [MarkdownBlock]
    let scope: MarkdownScope
    @Environment(\.kitText) private var style

    var body: some View {
        let gaps = MarkdownMetrics.gaps(blocks.map { MarkdownMetrics.margins($0, scope: scope, size: style.size) })
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks.indices, id: \.self) { index in
                MarkdownBlockView(block: blocks[index], scope: scope).padding(.top, gaps[index])
            }
        }
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let scope: MarkdownScope
    @Environment(\.kitText) private var style
    @Environment(\.kitListDepth) private var depth

    var body: some View {
        switch block {
        case .heading(let level, let inlines): MarkdownText(inlines: inlines, style: MarkdownMetrics.heading(level))
        case .paragraph(let inlines): MarkdownText(inlines: inlines, style: style)
        case .quote(let blocks): MarkdownQuote(blocks: blocks, scope: scope)
        case .list(let list): MarkdownListView(list: list, depth: depth)
        case .code(_, let lines): CodeSurface(lines: lines)
        default: MarkdownLeafView(block: block)
        }
    }
}

private struct MarkdownLeafView: View {
    let block: MarkdownBlock
    @Environment(\.kitTheme) private var theme

    var body: some View {
        switch block {
        case .table(let table): MarkdownTableView(table: table)
        case .rule: Rectangle().fill(Color(theme.tokens.border)).frame(height: 1).frame(maxWidth: .infinity)
        case .footnotes(let items): MarkdownFootnotes(items: items)
        default: EmptyView()
        }
    }
}

/// One paragraph or heading of inline runs.
struct MarkdownText: View {
    let inlines: [MarkdownInline]
    let style: TextStyle
    @Environment(\.kitTheme) private var theme

    var body: some View {
        Text(MarkdownRuns.attributed(inlines, style: style, theme: theme))
            .textLayout(style)
            .fixedSize(horizontal: false, vertical: true)
    }
}
