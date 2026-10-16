import CanvasCore
import SwiftUI

/// A run of children drawn as one `Text`, or one child drawn as its own view.
enum FlowSegment: Identifiable {
    case inline([ViewNode])
    case block(ViewNode)

    var id: Int {
        switch self {
        case .inline(let nodes): -1 - (nodes.first?.id ?? 0)
        case .block(let node): node.id
        }
    }
}

enum Flow {
    /// In flex and grid containers only text joins a run; elements are items.
    static let textOnly: Set<String> = [ViewNode.textType]
    /// In block containers (Text, Heading, slots, cells) inline code and keys join the text.
    static let phrasing: Set<String> = [ViewNode.textType, "Code", "Kbd"]

    /// Unknown types are left out here, so they take no stack spacing.
    static func segments(_ nodes: [ViewNode], inline: Set<String>) -> [FlowSegment] {
        var segments: [FlowSegment] = []
        var run: [ViewNode] = []
        for node in nodes where KitRegistry.knows(node.type) {
            if inline.contains(node.type) {
                run.append(node)
                continue
            }
            if !run.isEmpty { segments.append(.inline(run)) }
            run = []
            segments.append(.block(node))
        }
        if !run.isEmpty { segments.append(.inline(run)) }
        return segments
    }
}

struct SegmentView: View {
    let segment: FlowSegment

    var body: some View {
        switch segment {
        case .inline(let nodes): InlineText(nodes: nodes)
        case .block(let node): NodeView(node: node)
        }
    }
}

/// Children of a block container, top to bottom, with phrasing runs as text.
struct BlockFlow: View {
    let nodes: [ViewNode]

    var body: some View {
        let segments = Flow.segments(nodes, inline: Flow.phrasing)
        if nodes.count == 1, let only = nodes.first, only.isText {
            PlainText(node: only)
        } else if segments.count == 1, let only = segments.first {
            SegmentView(segment: only)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(segments) { SegmentView(segment: $0) }
            }
        }
    }
}

/// A slot's children as a block flow. It observes the slot node, so slot
/// content updates without re-rendering the owner.
struct SlotFlow: View {
    @ObservedObject var slot: ViewNode

    var body: some View { BlockFlow(nodes: slot.children) }
}

/// Text nodes and inline elements concatenated into one `Text`, so they
/// wrap as one paragraph.
struct InlineText: View {
    let nodes: [ViewNode]

    var body: some View {
        if nodes.count == 1, let only = nodes.first, only.isText {
            PlainText(node: only)
        } else {
            RunText(nodes: nodes)
        }
    }
}

/// One text node, the common case: it observes the node itself.
struct PlainText: View {
    @ObservedObject var node: ViewNode
    @Environment(\.kitText) private var style
    @Environment(\.kitTheme) private var theme

    var body: some View {
        let value = node.text ?? ""
        Text(verbatim: style.uppercase ? value.uppercased() : value)
            .styled(style, theme: theme)
            .modifier(LineBox(leading: style.leading))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Several nodes, with inline code and keys, as one attributed string.
private struct RunText: View {
    let nodes: [ViewNode]
    @Environment(\.kitText) private var style
    @Environment(\.kitTheme) private var theme
    @State private var revision = 0

    var body: some View {
        _ = revision
        return Text(InlineRuns.attributed(nodes, style: style, theme: theme))
            .styled(style, theme: theme)
            .textCase(style.uppercase ? .uppercase : nil)
            .modifier(LineBox(leading: style.leading))
            .fixedSize(horizontal: false, vertical: true)
            .onReceive(ViewNode.changes(nodes)) { _ in revision &+= 1 }
    }
}

enum InlineRuns {
    /// Thin spaces in the surrounding font pad inline code like CSS padding.
    static let pad = "\u{2009}"

    static func attributed(_ nodes: [ViewNode], style: TextStyle, theme: Theme) -> AttributedString {
        nodes.reduce(into: AttributedString()) { result, node in
            switch node.type {
            case "Code": result += chip(node.textContent, style: codeStyle(style), fill: theme.tokens.inlineCodeBg)
            case "Kbd": result += chip(node.textContent, style: kbdStyle(style), fill: theme.tokens.kbdBg)
            default: result += AttributedString(node.textContent)
            }
        }
    }

    static func codeStyle(_ base: TextStyle) -> TextStyle {
        base.with { $0.mono = true; $0.size = (base.size * 0.85).rounded(toPlaces: 2) }
    }

    static func kbdStyle(_ base: TextStyle) -> TextStyle {
        base.with { $0.mono = true; $0.size = 11.5; $0.weight = .medium }
    }

    static func chip(_ text: String, style: TextStyle, fill: RGBA) -> AttributedString {
        var padding = AttributedString(pad)
        padding.backgroundColor = Color(fill)
        var body = AttributedString(text)
        body.font = style.font
        body.backgroundColor = Color(fill)
        return padding + body + padding
    }
}

extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let scale = pow(10, CGFloat(places))
        return (self * scale).rounded() / scale
    }
}
