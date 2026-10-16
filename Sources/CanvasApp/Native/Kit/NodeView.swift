import CanvasCore
import SwiftUI

/// One node of the tree. It observes its node, so a props change
/// re-renders this node's view and not its parent or siblings.
struct NodeView: View {
    @ObservedObject var node: ViewNode

    var body: some View {
        KitProbe.record(node.id)
        var style = KitStyle(node.prop("style"))
        if KitRegistry.ownsPadding.contains(node.type) { style.padding = nil }
        return KitRegistry.view(for: node).modifier(StyleModifier(style: style))
    }
}

/// Counts body evaluations, for tests that check what a change re-renders.
enum KitProbe {
    nonisolated(unsafe) static var onBody: ((Int) -> Void)?

    static func record(_ id: Int) { onBody?(id) }
}

/// The view for each host element type in docs/native.md. Unknown types
/// render nothing.
enum KitRegistry {
    typealias Make = (ViewNode) -> AnyView

    /// Types that apply `style.padding` inside their own background.
    static let ownsPadding: Set<String> = ["Card"]

    static func knows(_ type: String) -> Bool { makers[type] != nil }

    static func view(for node: ViewNode) -> AnyView {
        makers[node.type]?(node) ?? AnyView(EmptyView())
    }

    private static let makers: [String: Make] = layout.merging(text) { $1 }.merging(data) { $1 }.merging(input) { $1 }

    private static let layout: [String: Make] = [
        ViewNode.textType: { AnyView(InlineText(nodes: [$0])) },
        "Stack": { AnyView(StackView(node: $0)) },
        "Row": { AnyView(RowView(node: $0)) },
        "Grid": { AnyView(GridView(node: $0)) },
        "Divider": { _ in AnyView(DividerView()) },
        "Spacer": { AnyView(SpacerView(node: $0)) },
        "Card": { AnyView(CardView(node: $0)) }
    ]

    private static let text: [String: Make] = [
        "Heading": { AnyView(HeadingView(node: $0)) },
        "Text": { AnyView(TextView(node: $0)) },
        "Code": { AnyView(CodeView(node: $0)) },
        "CodeBlock": { AnyView(CodeBlockView(node: $0)) },
        "Markdown": { AnyView(MarkdownView(node: $0)) },
        "Kbd": { AnyView(KbdView(node: $0)) },
        "KeyChips": { AnyView(KeyChipsView(node: $0)) }
    ]

    private static let data: [String: Make] = [
        "Table": { AnyView(TableView(node: $0)) },
        "Stat": { AnyView(StatView(node: $0)) },
        "Badge": { AnyView(BadgeView(node: $0)) },
        "Progress": { AnyView(ProgressBarView(node: $0)) },
        "BarChart": { AnyView(BarChartView(node: $0)) },
        "Sparkline": { AnyView(SparklineView(node: $0)) }
    ]

    private static let input: [String: Make] = [
        "Button": { AnyView(ButtonView(node: $0)) },
        "Input": { AnyView(InputView(node: $0)) },
        "TextArea": { AnyView(InputView(node: $0)) },
        "Select": { AnyView(SelectView(node: $0)) },
        "Checkbox": { AnyView(CheckboxView(node: $0)) },
        "Form": { AnyView(FormView(node: $0)) }
    ]
}
