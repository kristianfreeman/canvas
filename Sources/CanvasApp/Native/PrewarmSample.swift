/// A panel with every host element type in docs/native.md, and every
/// Markdown block and inline run, for `NativePrewarm`.
enum PrewarmSample {
    typealias Element = PrewarmElement

    static var ops: [[String: Any]] {
        Element.ops([.of("Stack", ["gap": 12], layout, data, form), markdown, footer])
    }

    static var layout: Element {
        .of("Card", ["padding": 14],
            .slot("title", [.text("Title")]), .slot("subtitle", [.text("Subtitle")]),
            .slot("actions", [.of("Badge", ["color": "success", "dot": true], .text("live"))]),
            .of("Row", ["gap": 8, "align": "center", "justify": "between", "wrap": true],
                .of("Heading", ["level": 2], .text("Heading")), .of("Spacer", ["size": 4]),
                .of("Text", ["size": "sm", "muted": true, "weight": "medium", "mono": true], .text("text")),
                .of("Code", [:], .text("code")), .of("Kbd", ["tone": "accent"], .text("Esc")),
                .of("KeyChips", ["keys": ["Hyper 1–7", "Cmd + K"]])),
            .of("Divider"),
            .of("Grid", ["columns": "max-content 1fr", "gap": 8],
                .of("Text", [:], .text("a")), .of("Text", ["color": "accent"], .text("b"))),
            .of("CodeBlock", ["lang": "ts", "lines": [[["s": "const", "c": "keyword"], ["s": " a = "],
                                                         ["s": "1", "c": "number"]]]]))
    }

    static var data: Element {
        .of("Stack", ["gap": 8],
            .of("Stat", ["delta": "12%", "tone": "up", "good": true],
                .slot("label", [.text("Deploys")]), .slot("value", [.text("48")]), .slot("hint", [.text("7 days")])),
            .of("Progress", ["value": 0.4, "color": "warning", "showValue": true], .slot("label", [.text("budget")])),
            .of("BarChart", ["data": [["value": 3], ["value": 5, "color": "teal"]], "max": 5, "height": 60,
                             "color": "accent"],
                .slot("label0", [.text("a")]), .slot("label1", [.text("b")])),
            .of("Sparkline", ["data": [1, 3, 2, 5], "width": 120, "height": 28, "color": "accent", "fill": true]),
            .of("Table", ["columns": [["key": "a"], ["key": "b", "align": "right"]]],
                .slot("head", [.of("TableCell", [:], .text("A")), .of("TableCell", ["align": "right"], .text("B"))]),
                .of("TableRow", ["key": "1"], .of("TableCell", [:], .text("x")), .of("TableCell", [:], .text("1")))))
    }

    static var form: Element {
        .of("Form", ["gap": 12],
            .of("Input", ["name": "a", "placeholder": "INC-1234"], .slot("label", [.text("Ticket")]),
                .slot("hint", [.text("hint")])),
            .of("TextArea", ["name": "b", "rows": 2], .slot("label", [.text("Comment")])),
            .of("Select", ["name": "c", "options": [["value": "us", "label": "US"], ["value": "eu", "label": "EU"]]],
                .slot("label", [.text("Region")])),
            .of("Checkbox", ["name": "d", "checked": true], .slot("label", [.text("Notify")])),
            .of("Row", ["gap": 8],
                .of("Button", ["variant": "secondary", "submit": true], .text("Reject")),
                .of("Button", ["variant": "primary", "submit": true], .text("Approve"))))
    }

    static func run(_ text: String, _ marks: [String: Any] = [:]) -> [String: Any] {
        ["t": "text", "s": text].merging(marks) { $1 }
    }

    static func para(_ inline: [[String: Any]]) -> [String: Any] { ["t": "p", "inl": inline] }

    static var markdown: Element {
        let inline: [[String: Any]] = [
            run("plain "), run("bold", ["b": true]), run(" italic", ["i": true]), run(" gone", ["del": true]),
            ["t": "code", "s": "code"], ["t": "br"], ["t": "link", "href": "https://example.com", "inl": [run("link")]],
            ["t": "fnref", "id": "fn1", "n": 1]
        ]
        let blocks: [[String: Any]] = [
            ["t": "h", "level": 1, "inl": [run("Heading")]], para(inline),
            ["t": "quote", "blocks": [para([run("quote")])]],
            ["t": "list", "ordered": true, "start": 1, "items": [["blocks": [para([run("one")])]]]],
            ["t": "list", "ordered": false,
             "items": [["task": true, "checked": true, "blocks": [para([run("done")])]]]],
            ["t": "code", "lang": "swift", "lines": [[["s": "let", "c": "keyword"], ["s": " a"]]]],
            ["t": "table", "align": ["left", "right"], "head": [[run("A")], [run("B")]], "rows": [[[run("1")], []]]],
            ["t": "hr"], ["t": "footnotes", "items": [["id": "fn1", "blocks": [para([run("note")])]]]]
        ]
        return .of("Markdown", ["blocks": blocks])
    }

    static var footer: Element {
        .of("Footer", ["buttons": ["OK", "Cancel"], "wait": true])
    }
}
