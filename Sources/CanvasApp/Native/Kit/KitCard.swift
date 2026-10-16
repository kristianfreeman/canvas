import CanvasCore
import SwiftUI

struct CardView: View {
    @ObservedObject var node: ViewNode
    @Environment(\.kitTheme) private var theme
    @Environment(\.kitFillsHeight) private var fillsHeight

    var body: some View {
        let padding = KitStyle(node.prop("style")).padding
            ?? EdgeInsets(all: KitValue.length(node.prop("padding")) ?? 16)
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: node.slotNode("title"), subtitle: node.slotNode("subtitle"),
                       actions: node.slotNode("actions"))
            BlockFlow(nodes: node.body)
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(theme.tokens.card)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(theme.tokens.border), lineWidth: 1))
        .environment(\.kitFillsHeight, false)
    }
}

private struct CardHeader: View {
    let title: ViewNode?
    let subtitle: ViewNode?
    let actions: ViewNode?

    var body: some View {
        if title != nil || subtitle != nil || actions != nil {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        SlotFlow(slot: title).kitText { $0 = TextStyle(size: 13, weight: .semibold, lineHeight: 1.35) }
                    }
                    if let subtitle {
                        SlotFlow(slot: subtitle).kitText { $0 = TextStyle(size: 12, ink: .muted, lineHeight: 1.55) }
                    }
                }
                Spacer(minLength: 0)
                if let actions {
                    HStack(spacing: 6) { SlotChildren(slot: actions) }.fixedSize()
                }
            }
            .padding(.bottom, 12)
        }
    }
}

/// A slot's children as flex items.
struct SlotChildren: View {
    @ObservedObject var slot: ViewNode

    var body: some View { FlexItems(nodes: slot.children) }
}

extension EdgeInsets {
    init(all value: CGFloat) {
        self.init(top: value, leading: value, bottom: value, trailing: value)
    }
}
