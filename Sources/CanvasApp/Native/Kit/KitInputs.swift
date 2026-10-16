import CanvasCore
import SwiftUI

/// A field's label above and hint below, when it has them.
struct FieldFrame<Content: View>: View {
    let label: ViewNode?
    let hint: ViewNode?
    @ViewBuilder let content: Content

    init(node: ViewNode, @ViewBuilder content: () -> Content) {
        label = node.slotNode("label")
        hint = node.slotNode("hint")
        self.content = content()
    }

    var body: some View {
        if label == nil && hint == nil {
            content
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let label {
                    SlotFlow(slot: label).kitText { $0 = TextStyle(size: 12.5, weight: .medium, ink: .soft) }
                }
                content
                if let hint { SlotFlow(slot: hint).kitText { $0 = TextStyle(size: 12, ink: .subtle) } }
            }
        }
    }
}

/// `.cv-input`: field background, strong border, radius 8; 34 pt tall, or
/// `rows` lines for a text area.
struct FieldChrome: ViewModifier {
    let multiline: Bool
    @Environment(\.kitTheme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 11)
            .padding(.vertical, multiline ? 9 : 0)
            .frame(maxWidth: .infinity, minHeight: multiline ? 60 : 34, maxHeight: multiline ? nil : 34,
                   alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(theme.tokens.field)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(theme.tokens.borderStrong), lineWidth: 1))
    }
}

/// `Input` and `TextArea`.
struct InputView: View {
    @ObservedObject var node: ViewNode
    @Environment(\.kitFields) private var fields
    @Environment(\.kitEvents) private var events
    @Environment(\.kitControls) private var controls
    @Environment(\.kitTheme) private var theme
    @State private var echo = EditEcho()

    var body: some View {
        let disabled = node.prop("disabled")?.isTrue == true
        FieldFrame(node: node) {
            field.modifier(FieldChrome(multiline: multiline))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onChange(of: node.prop("value")) { _, value in adopt(value) }
    }

    private var multiline: Bool { node.type == "TextArea" }

    private var rows: Int { max(1, KitValue.int(node.prop("rows"), multiline ? 4 : 1)) }

    private var style: TextStyle { TextStyle(size: 14, lineHeight: multiline ? 1.5 : 1.4) }

    @ViewBuilder private var field: some View {
        let placeholder = node.prop("placeholder")?.string ?? ""
        if controls == .still {
            StillText(text: FormFields.text(node, fields: fields), placeholder: placeholder,
                      secure: node.prop("type")?.string == "password", rows: multiline ? rows : nil)
                .textLayout(style)
        } else {
            LiveTextField(binding: binding, placeholder: placeholder, secure: node.prop("type")?.string == "password",
                          rows: multiline ? rows : nil, onSubmit: { actions.submitForm(of: node) })
                .textLayout(style)
        }
    }

    private var actions: KitActions { KitActions(events: events.target, fields: fields) }

    private var binding: Binding<String> {
        Binding {
            FormFields.text(node, fields: fields)
        } set: { text in
            if node.prop("onChange")?.function != nil { echo.sent(text) }
            actions.change(node, to: .string(text))
        }
    }

    private func adopt(_ value: JSONValue?) {
        let text = value?.string ?? value?.number.map(FormJSValue.string) ?? ""
        if echo.received(text) { fields?.clear(node.id) }
    }
}

private struct LiveTextField: View {
    let binding: Binding<String>
    let placeholder: String
    let secure: Bool
    let rows: Int?
    let onSubmit: () -> Void
    @Environment(\.kitTheme) private var theme

    var body: some View {
        let prompt = Text(placeholder).foregroundColor(Color(theme.tokens.fgSubtle))
        Group {
            if secure {
                SecureField("", text: binding, prompt: prompt)
            } else if let rows {
                TextField("", text: binding, prompt: prompt, axis: .vertical).lineLimit(rows, reservesSpace: true)
            } else {
                TextField("", text: binding, prompt: prompt)
            }
        }
        .textFieldStyle(.plain)
        .onSubmit { if rows == nil { onSubmit() } }
    }
}

/// A field's text as a plain `Text`, for snapshots.
struct StillText: View {
    let text: String
    let placeholder: String
    let secure: Bool
    let rows: Int?
    @Environment(\.kitTheme) private var theme

    var body: some View {
        let shown = secure ? String(repeating: "•", count: text.count) : text
        Text(shown.isEmpty ? placeholder : shown)
            .foregroundColor(shown.isEmpty ? Color(theme.tokens.fgSubtle) : nil)
            .lineLimit(rows ?? 1, reservesSpace: rows != nil)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
