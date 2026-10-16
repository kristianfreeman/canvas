import AppKit
import CanvasCore
import SwiftUI

struct SelectOption: Equatable {
    let value: String
    let label: String
    let disabled: Bool

    static func list(_ value: JSONValue?) -> [Self] {
        (value?.array ?? []).compactMap { option in
            if let text = option.string { return Self(value: text, label: text, disabled: false) }
            guard let value = option["value"]?.string else { return nil }
            return Self(value: value, label: option["label"]?.string ?? value,
                        disabled: option["disabled"]?.isTrue == true)
        }
    }
}

/// `Select`: the input chrome with the chosen label and a chevron. A click
/// opens a native menu, so nothing AppKit-backed sits in the view tree.
struct SelectView: View {
    @ObservedObject var node: ViewNode
    @Environment(\.kitFields) private var fields
    @Environment(\.kitEvents) private var events
    @Environment(\.kitTheme) private var theme
    @State private var revision = 0

    var body: some View {
        _ = revision
        return field(options: SelectOption.list(node.prop("options")), selected: FormFields.text(node, fields: fields))
            .disabled(node.prop("disabled")?.isTrue == true)
            .opacity(node.prop("disabled")?.isTrue == true ? 0.5 : 1)
            .onChange(of: node.prop("value")) { fields?.clear(node.id) }
    }

    private func field(options: [SelectOption], selected: String) -> some View {
        FieldFrame(node: node) {
            Button { choose(from: options, selected: selected) } label: {
                HStack(spacing: 8) {
                    Text(options.first { $0.value == selected }?.label ?? selected)
                        .textLayout(TextStyle(size: 14, lineHeight: 1.4)).lineLimit(1)
                    Spacer(minLength: 0)
                    Chevron().stroke(Color(theme.tokens.fgSubtle), lineWidth: 1.5).frame(width: 8, height: 4.5)
                        .padding(.trailing, 2)
                }
                .modifier(FieldChrome(multiline: false))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func choose(from options: [SelectOption], selected: String) {
        let picker = MenuPicker(options: options, selected: selected)
        guard let index = picker.run() else { return }
        KitActions(events: events.target, fields: fields).change(node, to: .string(options[index].value))
        revision &+= 1
    }
}

private struct Chevron: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
    }
}

/// Shows options in an `NSMenu` at the mouse and returns the picked index.
final class MenuPicker: NSObject {
    private let options: [SelectOption]
    private let selected: String
    private var picked: Int?

    init(options: [SelectOption], selected: String) {
        self.options = options
        self.selected = selected
    }

    func run() -> Int? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, option) in options.enumerated() {
            let item = NSMenuItem(title: option.label, action: #selector(pick(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            item.isEnabled = !option.disabled
            item.state = option.value == selected ? .on : .off
            menu.addItem(item)
        }
        let current = options.firstIndex { $0.value == selected }.flatMap { menu.item(at: $0) }
        menu.popUp(positioning: current, at: NSEvent.mouseLocation, in: nil)
        return picked
    }

    @objc private func pick(_ item: NSMenuItem) { picked = item.tag }
}

struct CheckboxView: View {
    @ObservedObject var node: ViewNode
    @Environment(\.kitFields) private var fields
    @Environment(\.kitEvents) private var events
    @State private var revision = 0

    var body: some View {
        _ = revision
        return toggle(checked: FormFields.checked(node, fields: fields))
            .buttonStyle(.plain)
            .disabled(node.prop("disabled")?.isTrue == true)
            .opacity(node.prop("disabled")?.isTrue == true ? 0.5 : 1)
            .onChange(of: node.prop("checked")) { fields?.clear(node.id) }
    }

    private func toggle(checked: Bool) -> some View {
        Button {
            KitActions(events: events.target, fields: fields).change(node, to: .bool(!checked))
            revision &+= 1
        } label: {
            HStack(alignment: .top, spacing: 9) {
                CheckGlyph(checked: checked, size: 16, radius: 4.5, filled: true).padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    if let label = node.slotNode("label") { SlotFlow(slot: label) }
                    if let hint = node.slotNode("hint") {
                        SlotFlow(slot: hint).kitText { $0 = TextStyle(size: 12, ink: .subtle) }
                    }
                }
                .kitText { $0 = TextStyle(size: 14) }
            }
            .contentShape(Rectangle())
        }
    }
}

/// The kit's checkbox square, also used for Markdown task items.
struct CheckGlyph: View {
    let checked: Bool
    let size: CGFloat
    let radius: CGFloat
    /// The form checkbox sits on the field color; task items are hollow.
    let filled: Bool
    @Environment(\.kitTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color(checked ? theme.accent : filled ? theme.tokens.field : .clear))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(Color(checked ? theme.accent : theme.tokens.borderHover), lineWidth: 1.5))
            .overlay {
                if checked {
                    CheckMark().stroke(Color(theme.accentForeground), lineWidth: 1.75).padding(size * 0.27)
                }
            }
            .frame(width: size, height: size)
    }
}

private struct CheckMark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.05))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.05))
        }
    }
}

struct FormView: View {
    @ObservedObject var node: ViewNode

    var body: some View {
        VStack(alignment: .leading, spacing: KitValue.length(node.prop("gap")) ?? 16) {
            FlexItems(nodes: node.body)
        }
    }
}
