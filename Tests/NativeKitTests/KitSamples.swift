import Foundation

/// Representative panels as the runtime would send them, after the kit
/// shim turns props into host elements and slots.
enum KitSamples {
    struct StatSample {
        let label, value, delta, tone: String
        let trend: [Double]
        let color: String
    }

    static func stat(_ sample: StatSample) -> Element {
        node("Card", ["padding": 14],
             node("Stack", ["gap": 10],
                  node("Stat", ["delta": sample.delta, "tone": sample.tone, "good": true],
                       slot("label", text(sample.label)), slot("value", text(sample.value))),
                  node("Sparkline", ["data": sample.trend, "width": "100%", "height": 28, "color": sample.color,
                                     "fill": true])))
    }

    static var statsCard: [Element] {
        [node("Stack", ["gap": 14],
              node("Grid", ["columns": 2, "gap": 12],
                   stat(StatSample(label: "Deploys, 7 days", value: "48", delta: "+12%", tone: "up",
                                   trend: [4, 6, 5, 7, 6, 9, 11], color: "accent")),
                   stat(StatSample(label: "p95 build time", value: "6m 12s", delta: "-38s", tone: "down",
                                   trend: [8.1, 7.6, 7.9, 7.2, 6.8, 6.5, 6.2], color: "teal"))),
              node("Card", [:],
                   slot("title", text("Error budget")), slot("subtitle", text("30-day window, remaining")),
                   slot("actions", node("Badge", ["color": "warning", "dot": true], text("1 at risk"))),
                   node("Stack", ["gap": 13], children: [
                       ("api-gateway", 0.72, "green"), ("billing-worker", 0.34, "warning"), ("search", 0.12, "danger")
                   ].map { name, value, color in
                       node("Progress", ["value": value, "color": color, "showValue": true], slot("label", text(name)))
                   })),
              node("Row", ["gap": 8], node("Badge", ["color": "success", "dot": true], text("live")),
                   node("Badge", ["color": "info"], text("rolling")),
                   node("Badge", ["color": "muted"], text("v2.14.0"))))]
    }

    static let deploys = [
        ["api-gateway", "v2.14.0", "kristian", "5m 48s", "rolling"],
        ["web", "v8.3.1", "maya", "4m 02s", "live"],
        ["billing-worker", "v1.9.4", "sam", "7m 31s", "failed"],
        ["search", "v3.0.0", "jordan", "9m 10s", "rolled back"]
    ]

    static let statusColor = ["live": "success", "rolling": "info", "failed": "danger", "rolled back": "warning"]

    static func deployRow(_ row: [String], key: Int) -> Element {
        node("TableRow", ["key": key],
             node("TableCell", [:], node("Text", ["weight": "medium"], text(row[0]))),
             node("TableCell", [:], node("Text", ["mono": true, "muted": true], text(row[1]))),
             node("TableCell", [:], text(row[2])),
             node("TableCell", ["align": "right"], text(row[3])),
             node("TableCell", ["align": "right"],
                  node("Badge", ["color": statusColor[row[4]] ?? "muted", "dot": true], text(row[4]))))
    }

    static func table(rows: [[String]]) -> Element {
        let columns: [[String: Any]] = [
            ["key": "service"], ["key": "version"], ["key": "author"],
            ["key": "duration", "align": "right"], ["key": "status", "align": "right"]
        ]
        let head = ["Service", "Version", "Author", "Duration", "Status"].map { node("TableCell", [:], text($0)) }
        return node("Table", ["columns": columns],
                    children: [.slot("head", head)] + rows.enumerated().map { deployRow($1, key: $0) })
    }

    static var tableCard: [Element] {
        [node("Card", [:], slot("title", text("Recent deploys")),
              slot("actions", node("Text", ["size": "sm", "muted": true], text("production"))),
              table(rows: deploys))]
    }

    static func keyRow(_ keys: String, _ desc: String) -> [Element] {
        [node("KeyChips", ["keys": keys]),
         node("Text", ["size": "sm"], text(desc))]
    }

    static var keyChips: [Element] {
        let rows = [
            ("Hyper 1–7", "Go to workspace, again to go back"), ("Hyper ← ↑ ↓ →", "Move window"),
            ("Caps Lock tap", "Escape"), ("Hyper W → 1–7", "Send window to workspace"), ("Cmd + K", "Command palette")
        ]
        return [node("Stack", ["gap": 6],
                     node("Heading", ["level": 4], text("Windows")),
                     node("Grid", ["columns": "max-content 1fr", "gap": 8], children: rows.flatMap(keyRow)),
                     node("Row", ["gap": 6, "justify": "end"], node("Kbd", [:], text("Esc")),
                          node("Text", ["size": "sm", "muted": true], text("to close"))))]
    }

    static var form: [Element] {
        [node("Form", ["gap": 16],
              node("Stack", ["gap": 6],
                   node("Row", ["gap": 8], node("Badge", ["color": "warning", "dot": true], text("Needs approval")),
                        node("Badge", ["color": "muted"], text("production"))),
                   node("Text", ["size": "lg", "weight": "semibold"], text("Deploy api-gateway to production")),
                   node("Text", ["muted": true], node("Code", [:], text("api-gateway")), text(" v2.13.2 → v2.14.0"))),
              node("Input", ["name": "ticket", "placeholder": "INC-1234"], slot("label", text("Ticket"))),
              node("Input", ["name": "replicas", "type": "number", "value": "3"], slot("label", text("Replicas")),
                   slot("hint", text("Between 1 and 12"))),
              node("Select", ["name": "region", "value": "eu", "options": [
                  ["value": "us", "label": "US East"], ["value": "eu", "label": "EU West"]
              ]], slot("label", text("Region"))),
              node("Checkbox", ["name": "notify", "checked": true], slot("label", text("Notify #deploys"))),
              node("TextArea", ["name": "comment", "placeholder": "Optional note for the agent", "rows": 3],
                   slot("label", text("Comment"))),
              node("Row", ["gap": 8],
                   node("Text", ["size": "sm", "muted": true], text("The agent is waiting for your answer.")),
                   node("Spacer"),
                   node("Button", ["variant": "secondary", "submit": true, "name": "decision", "value": "reject"],
                        text("Reject")),
                   node("Button", ["variant": "primary", "submit": true, "name": "decision", "value": "approve"],
                        text("Approve")))),
         node("Footer", ["buttons": ["Approve", "Later"], "wait": true])]
    }
}
