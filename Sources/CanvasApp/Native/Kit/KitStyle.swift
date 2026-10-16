import CanvasCore
import SwiftUI

/// Reads kit prop values: lengths are numbers or `px` strings (docs/native.md).
enum KitValue {
    static func length(_ value: JSONValue?) -> CGFloat? {
        switch value {
        case .number(let number) where number.isFinite: CGFloat(number)
        case .string(let text):
            Double(text.hasSuffix("px") ? String(text.dropLast(2)) : text).flatMap { $0.isFinite ? CGFloat($0) : nil }
        default: nil
        }
    }

    static func align(_ value: JSONValue?) -> TextAlign? { value?.string.flatMap(TextAlign.init) }

    static func number(_ value: JSONValue?) -> Double? { value?.number.flatMap { $0.isFinite ? $0 : nil } }

    /// A whole number, or `fallback` for anything missing, non-finite or out of range.
    static func int(_ value: JSONValue?, _ fallback: Int) -> Int {
        guard let number = number(value), abs(number) < 1e9 else { return fallback }
        return Int(number)
    }
}

extension TextAlign {
    var horizontal: HorizontalAlignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    var frame: Alignment { Alignment(horizontal: horizontal, vertical: .center) }

    var multiline: TextAlignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }
}

/// The allowed `style` subset as SwiftUI modifiers.
struct KitStyle: Equatable {
    var margin = EdgeInsets()
    var padding: EdgeInsets?
    var width: CGFloat?
    var minWidth: CGFloat?
    var maxWidth: CGFloat?
    var height: CGFloat?
    var flex: Double?
    var opacity: Double?
    var textAlign: TextAlign?

    init(_ value: JSONValue?) {
        guard let style = value?.object, !style.isEmpty else { return }
        margin = Self.edges(style, "margin") ?? EdgeInsets()
        padding = Self.edges(style, "padding")
        width = KitValue.length(style["width"])
        minWidth = KitValue.length(style["minWidth"])
        maxWidth = KitValue.length(style["maxWidth"])
        height = KitValue.length(style["height"])
        flex = KitValue.number(style["flex"])
        opacity = KitValue.number(style["opacity"])
        textAlign = KitValue.align(style["textAlign"])
    }

    var isEmpty: Bool { self == Self(nil) }

    /// `flex` and `textAlign` make the node take the full width.
    var fills: Bool { (flex ?? 0) > 0 || textAlign != nil }

    /// `margin` or `padding` with its four side keys; nil when none is set.
    private static func edges(_ style: [String: JSONValue], _ name: String) -> EdgeInsets? {
        let all = KitValue.length(style[name])
        let sides = ["Top", "Left", "Bottom", "Right"].map { KitValue.length(style[name + $0]) ?? all }
        guard sides.contains(where: { $0 != nil }) else { return nil }
        return EdgeInsets(top: sides[0] ?? 0, leading: sides[1] ?? 0, bottom: sides[2] ?? 0, trailing: sides[3] ?? 0)
    }
}

struct StyleModifier: ViewModifier {
    let style: KitStyle

    func body(content: Content) -> some View {
        if style.isEmpty {
            content
        } else {
            styled(content)
        }
    }

    private func styled(_ content: Content) -> some View {
        let align = style.textAlign?.frame ?? .leading
        return content
            .multilineTextAlignment(style.textAlign?.multiline ?? .leading)
            .padding(style.padding ?? EdgeInsets())
            .frame(width: style.width, height: style.height, alignment: align)
            .frame(minWidth: style.minWidth, maxWidth: style.maxWidth ?? (style.fills ? .infinity : nil),
                   alignment: align)
            .padding(style.margin)
            .opacity(style.opacity ?? 1)
    }
}
