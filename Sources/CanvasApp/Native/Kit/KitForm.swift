import CanvasCore
import Foundation

/// Field values edited in one panel, by node id. Props give the initial and
/// controlled values; an edit lives here until the props catch up.
final class FieldStore {
    private var values: [Int: JSONValue] = [:]

    func value(_ id: Int) -> JSONValue? { values[id] }

    func set(_ value: JSONValue, for id: Int) { values[id] = value }

    func clear(_ id: Int) { values[id] = nil }
}

/// What a field shows and submits: its edit, else its props.
enum FormFields {
    static let types: Set<String> = ["Input", "TextArea", "Select", "Checkbox"]
    static let numberTypes: Set<String> = ["number", "range"]

    static func text(_ node: ViewNode, fields: FieldStore?) -> String {
        if let edited = fields?.value(node.id)?.string { return edited }
        switch node.prop("value") {
        case .string(let text): return text
        case .number(let number): return FormJSValue.string(number)
        default: return node.type == "Select" ? firstOption(node) : ""
        }
    }

    static func checked(_ node: ViewNode, fields: FieldStore?) -> Bool {
        if case .bool(let edited) = fields?.value(node.id) { return edited }
        return node.prop("checked")?.isTrue == true
    }

    /// A select without a value shows its first enabled option, as the DOM does.
    static func firstOption(_ node: ViewNode) -> String {
        let options = node.prop("options")?.array ?? []
        return options.first { $0["disabled"]?.isTrue != true }?["value"]?.string ?? ""
    }

    /// Named, enabled fields under `form` in order: checkboxes as booleans,
    /// number inputs as numbers (null when empty or not a number), the rest
    /// as strings, plus the submitting button's `name` and `value`.
    static func values(in form: ViewNode, fields: FieldStore?, submitter: ViewNode?) -> [String: Any] {
        var values: [String: Any] = [:]
        for node in form.subtree where types.contains(node.type) {
            guard let name = node.prop("name")?.string, !name.isEmpty, node.prop("disabled")?.isTrue != true else {
                continue
            }
            values[name] = value(node, fields: fields)
        }
        if let submitter, let name = submitter.prop("name")?.string, !name.isEmpty {
            values[name] = buttonValue(submitter.prop("value"))
        }
        return values
    }

    static func value(_ node: ViewNode, fields: FieldStore?) -> Any {
        if node.type == "Checkbox" { return checked(node, fields: fields) }
        let text = text(node, fields: fields)
        guard node.type == "Input", numberTypes.contains(node.prop("type")?.string ?? "") else { return text }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSNull() : Double(trimmed).map { $0 as Any } ?? NSNull()
    }

    /// A DOM button's `value` is a string: numbers as JS prints them, anything else empty.
    static func buttonValue(_ value: JSONValue?) -> String {
        switch value {
        case .string(let text): text
        case .number(let number): FormJSValue.string(number)
        default: ""
        }
    }
}

enum FormJSValue {
    /// `String(n)` in JavaScript for ordinary numbers: no `.0` on whole numbers.
    static func string(_ number: Double) -> String {
        guard number.isFinite else { return number.isNaN ? "NaN" : number > 0 ? "Infinity" : "-Infinity" }
        if number == number.rounded(), abs(number) < 1e21 { return String(format: "%.0f", number) }
        return "\(number)"
    }
}

/// What the kit's controls do, apart from drawing: function props, form
/// submits and results.
struct KitActions {
    let events: NativeEvents?
    let fields: FieldStore?

    func press(_ button: ViewNode) {
        guard button.prop("disabled")?.isTrue != true else { return }
        if let click = button.prop("onClick")?.function {
            events?.invoke(click, [])
            return
        }
        let form = button.ancestor("Form")
        if let form, button.prop("submit").map(\.isTrue) ?? true {
            submit(form, submitter: button)
        } else if let value = button.prop("value"), value != .null {
            events?.submit(value.any)
        }
    }

    func submit(_ form: ViewNode, submitter: ViewNode?) {
        let values = FormFields.values(in: form, fields: fields, submitter: submitter)
        if let handler = form.prop("onSubmit")?.function {
            events?.invoke(handler, [values])
        } else {
            events?.submit(values)
        }
    }

    /// A table row or sortable header: `onClick` with no arguments.
    func click(_ node: ViewNode) {
        if let handler = node.prop("onClick")?.function { events?.invoke(handler, []) }
    }

    /// Return in a single-line input submits its form.
    func submitForm(of node: ViewNode) {
        if let form = node.ancestor("Form") { submit(form, submitter: nil) }
    }

    /// Records an edit and calls `onChange` with `[{value}]`, or `[{checked}]` for a checkbox.
    func change(_ node: ViewNode, to value: JSONValue) {
        fields?.set(value, for: node.id)
        guard let handler = node.prop("onChange")?.function else { return }
        events?.invoke(handler, [[node.type == "Checkbox" ? "checked" : "value": value.any]])
    }
}

/// Values sent through `onChange` that the props haven't echoed back yet.
/// While some are pending, a props value that's one of them is stale and
/// the local edit stays; any other props value replaces the edit.
struct EditEcho {
    private(set) var pending: [String] = []

    mutating func sent(_ value: String) {
        pending.append(value)
        if pending.count > 64 { pending.removeFirst() }
    }

    /// True when the props value should replace the local edit.
    mutating func received(_ value: String) -> Bool {
        guard let index = pending.firstIndex(of: value) else {
            pending.removeAll()
            return true
        }
        pending.removeFirst(index + 1)
        return pending.isEmpty
    }
}
