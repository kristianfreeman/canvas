@testable import CanvasApp
import CanvasCore
import Foundation
import Testing
import TestSupport

@Suite @MainActor struct NativeFormTests {
    static let fields: [Element] = [
        node("Input", ["name": "title", "value": "Hi"]),
        node("Input", ["name": "count", "type": "number", "value": "3"]),
        node("Input", ["name": "blank", "type": "number"]),
        node("Input", ["value": "unnamed"]),
        node("Input", ["name": "off", "value": "x", "disabled": true]),
        node("Checkbox", ["name": "ok", "checked": true]),
        node("Checkbox", ["name": "maybe"]),
        node("Select", ["name": "env", "options": [["value": "dev", "disabled": true], ["value": "staging"]]]),
        node("TextArea", ["name": "note"])
    ]

    static func form(_ props: [String: Any] = [:]) throws -> ViewTree {
        try tree(node("Form", props, children: [node("Stack", [:], children: fields)] + [
            node("Button", ["submit": true, "name": "decision", "value": "approve"], text("Approve")),
            node("Button", ["submit": true, "value": 7], text("Unnamed"))
        ]))
    }

    static func find(_ tree: ViewTree, _ type: String, _ index: Int = 0) throws -> ViewNode {
        let matches = tree.root.subtree.filter { $0.type == type }
        return try #require(index < matches.count ? matches[index] : nil)
    }

    @Test func submitCollectsNamedFields() throws {
        let tree = try Self.form()
        let events = RecordingEvents()
        KitActions(events: events, fields: FieldStore()).press(try Self.find(tree, "Button"))
        let values = try #require(events.submitted.first as? [String: Any])
        #expect(canonical(values) == canonical([
            "title": "Hi", "count": 3.0, "blank": NSNull(), "ok": true, "maybe": false, "env": "staging", "note": "",
            "decision": "approve"
        ] as [String: Any]))
        #expect(events.invoked.isEmpty)
    }

    @Test func editsWinOverPropsAndNumbersParse() throws {
        let tree = try Self.form()
        let fields = FieldStore()
        let events = RecordingEvents()
        let actions = KitActions(events: events, fields: fields)
        actions.change(try Self.find(tree, "Input", 1), to: .string(" 12.5 "))
        actions.change(try Self.find(tree, "Input", 0), to: .string("edited"))
        actions.change(try Self.find(tree, "Checkbox", 0), to: .bool(false))
        actions.change(try Self.find(tree, "Select"), to: .string("dev"))
        actions.press(try Self.find(tree, "Button", 1))
        let values = try #require(events.submitted.first as? [String: Any])
        #expect(values["count"] as? Double == 12.5)
        #expect(values["title"] as? String == "edited")
        #expect(values["ok"] as? Bool == false)
        #expect(values["env"] as? String == "dev")
        #expect(values["decision"] == nil)
        actions.change(try Self.find(tree, "Input", 1), to: .string("abc"))
        #expect(FormFields.value(try Self.find(tree, "Input", 1), fields: fields) is NSNull)
    }

    @Test func onSubmitGetsValuesInsteadOfAResult() throws {
        let tree = try Self.form(["onSubmit": ["$fn": 9]])
        let events = RecordingEvents()
        KitActions(events: events, fields: nil).submitForm(of: try Self.find(tree, "Input"))
        #expect(events.submitted.isEmpty)
        let call = try #require(events.invoked.first)
        #expect(call.fn == 9)
        let values = try #require(call.args.first as? [String: Any])
        #expect(values["title"] as? String == "Hi" && values["decision"] == nil)
    }

    @Test func buttonsOutsideAFormSubmitTheirValue() throws {
        let tree = try tree(
            node("Button", ["value": ["choice": "a"]], text("A")),
            node("Button", ["value": "b", "onClick": ["$fn": 4]], text("B")),
            node("Button", ["value": "c", "disabled": true], text("C")),
            node("Button", [:], text("D")))
        let events = RecordingEvents()
        let actions = KitActions(events: events, fields: nil)
        for button in tree.root.children { actions.press(button) }
        #expect(events.submitted.count == 1)
        #expect(canonical(events.submitted.first) == canonical(["choice": "a"]))
        #expect(events.invoked.map(\.fn) == [4])
        #expect(events.invoked.first?.args.isEmpty == true)
    }

    @Test func onChangeSendsValueOrChecked() throws {
        let tree = try tree(node("Input", ["name": "q", "onChange": ["$fn": 1]]),
                            node("Checkbox", ["name": "c", "onChange": ["$fn": 2]]))
        let events = RecordingEvents()
        let actions = KitActions(events: events, fields: FieldStore())
        actions.change(tree.root.children[0], to: .string("abc"))
        actions.change(tree.root.children[1], to: .bool(true))
        #expect(events.invoked.map(\.fn) == [1, 2])
        #expect(canonical(events.invoked.map(\.args)) == canonical([[["value": "abc"]], [["checked": true]]]))
    }

    @Test func editEchoKeepsTypingAheadOfProps() {
        var echo = EditEcho()
        echo.sent("a")
        echo.sent("ab")
        #expect(echo.received("a") == false)
        #expect(echo.received("ab") == true)
        echo.sent("x")
        #expect(echo.received("X") == true)
        #expect(echo.received("anything") == true)
    }

    @Test func linksOpenOnlyForWebAndMail() throws {
        let events = RecordingEvents()
        for link in ["https://a.b", "http://a.b", "mailto:k@a.b", "file:///etc/passwd", "javascript:alert(1)", "x"] {
            LinkPolicy.open(try #require(URL(string: link)), with: events)
        }
        #expect(events.opened.map(\.absoluteString) == ["https://a.b", "http://a.b", "mailto:k@a.b"])
    }

    @Test func buttonValueIsADOMString() {
        #expect(FormFields.buttonValue(.number(7)) == "7")
        #expect(FormFields.buttonValue(.number(1.5)) == "1.5")
        #expect(FormFields.buttonValue(.string("go")) == "go")
        #expect(FormFields.buttonValue(.bool(true)).isEmpty)
    }
}
