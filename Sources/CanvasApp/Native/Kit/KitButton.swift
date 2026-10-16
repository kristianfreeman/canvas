import CanvasCore
import SwiftUI

enum ButtonVariant: String {
    case primary, secondary, ghost, danger
}

struct ButtonView: View {
    @ObservedObject var node: ViewNode
    @Environment(\.kitEvents) private var events
    @Environment(\.kitFields) private var fields

    var body: some View {
        Button {
            KitActions(events: events.target, fields: fields).press(node)
        } label: {
            BlockFlow(nodes: node.children)
        }
        .buttonStyle(KitButtonStyle(variant: ButtonVariant(rawValue: node.prop("variant")?.string ?? "") ?? .secondary))
        .disabled(node.prop("disabled")?.isTrue == true)
    }
}

struct KitButtonStyle: ButtonStyle {
    let variant: ButtonVariant
    var hint: String?

    func makeBody(configuration: Configuration) -> some View {
        KitButtonBody(configuration: configuration, variant: variant, hint: hint)
    }
}

/// `.cv-btn`: 32 pt tall, 14 pt sides, radius 8, 13 pt medium label.
private struct KitButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let variant: ButtonVariant
    let hint: String?
    @Environment(\.kitTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        let colors = ButtonColors(theme: theme, variant: variant, hovering: hovering)
        HStack(spacing: 8) {
            configuration.label
                .kitText { $0 = TextStyle(size: 13, weight: .medium, ink: .custom(colors.text), lineHeight: 1) }
                .lineLimit(1)
                .fixedSize()
            if let hint {
                Text(hint).font(.custom(KitFont.mono, fixedSize: 11)).foregroundColor(Color(colors.text))
                    .opacity(0.6).padding(.trailing, -3)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(colors.fill)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(colors.border), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .opacity(enabled ? 1 : 0.45)
        .offset(y: configuration.isPressed ? 0.5 : 0)
        .onHover { hovering = $0 }
    }
}

struct ButtonColors {
    let text, fill, border: RGBA

    init(theme: Theme, variant: ButtonVariant, hovering: Bool) {
        let tokens = theme.tokens
        switch variant {
        case .primary:
            let fill = hovering ? theme.accentHover : theme.accent
            (text, self.fill, border) = (theme.accentForeground, fill, fill)
        case .secondary:
            (text, fill, border) = (tokens.fg, hovering ? tokens.cardHover : tokens.card,
                                    hovering ? tokens.borderHover : tokens.borderStrong)
        case .ghost:
            (text, fill, border) = (hovering ? tokens.fg : tokens.fgSoft, hovering ? tokens.cardHover : .clear, .clear)
        case .danger:
            (text, fill, border) = (theme.ink(theme.danger), theme.danger.opacity(hovering ? 0.15 : 0.09),
                                    theme.danger.opacity(hovering ? 0.34 : 0.24))
        }
    }
}

/// The panel footer: `buttons` right-aligned, the first (primary) rightmost
/// with its ⌘↩ hint.
struct FooterView: View {
    @ObservedObject var node: ViewNode
    @Environment(\.kitEvents) private var events

    var body: some View {
        let labels = (node.prop("buttons")?.array ?? []).compactMap(\.string).filter { !$0.isEmpty }
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            ForEach(Array(labels.enumerated().reversed()), id: \.offset) { index, label in
                Button { events.target?.submit(label) } label: { InlineLabel(text: label) }
                    .buttonStyle(KitButtonStyle(variant: index == 0 ? .primary : .secondary,
                                                hint: index == 0 ? "⌘↩" : nil))
                    .keyboardShortcut(index == 0 ? KeyboardShortcut(.return, modifiers: .command) : nil)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 20, bottom: 18, trailing: 20))
    }
}
