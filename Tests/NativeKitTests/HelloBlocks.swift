import Foundation

/// examples/hello.md as Markdown blocks, with highlight scopes as the
/// runtime's highlight.js would give them.
enum HelloBlocks {
    static func run(_ value: String, _ marks: [String: Any] = [:]) -> [String: Any] {
        ["t": "text", "s": value].merging(marks) { $1 }
    }

    static func code(_ value: String) -> [String: Any] { ["t": "code", "s": value] }

    static func para(_ inl: [[String: Any]]) -> [String: Any] { ["t": "p", "inl": inl] }

    static func heading(_ level: Int, _ value: String) -> [String: Any] {
        ["t": "h", "level": level, "inl": [run(value)]]
    }

    /// `⟨scope text⟩` marks a token; everything else is plain.
    static func lines(_ source: String) -> [[[String: Any]]] {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            var tokens: [[String: Any]] = []
            var rest = Substring(line)
            while !rest.isEmpty {
                guard let open = rest.firstIndex(of: "⟨") else {
                    tokens.append(["s": String(rest)])
                    break
                }
                if open > rest.startIndex { tokens.append(["s": String(rest[..<open])]) }
                let close = rest[open...].firstIndex(of: "⟩") ?? rest.endIndex
                let inner = rest[rest.index(after: open)..<close]
                let space = inner.firstIndex(of: " ") ?? inner.endIndex
                tokens.append(["s": String(inner[inner.index(after: space)...]), "c": String(inner[..<space])])
                rest = close < rest.endIndex ? rest[rest.index(after: close)...] : ""
            }
            return tokens
        }
    }

    static func fence(_ lang: String, _ source: String) -> [String: Any] {
        ["t": "code", "lang": lang, "lines": lines(source)]
    }

    static let typescript = """
    ⟨keyword import⟩ { Card, Stat } ⟨keyword from⟩ ⟨string 'canvas'⟩

    ⟨keyword export⟩ ⟨keyword default⟩ ⟨keyword function⟩ ⟨title Uptime⟩({ data }: { ⟨attr data⟩: { ⟨attr uptime⟩: \
    ⟨built_in number⟩ } }) {
      ⟨keyword return⟩ (
        <⟨tag Card⟩ ⟨attr title⟩=⟨string "API"⟩>
          <⟨tag Stat⟩ ⟨attr label⟩=⟨string "Uptime"⟩ ⟨attr value⟩={⟨string `${data.uptime}%`⟩} \
    ⟨attr delta⟩=⟨string "+0.02%"⟩ />
        </⟨tag Card⟩>
      )
    }
    """

    static let bash = """
    ⟨comment # Ask a question and wait for the answer⟩
    ⟨built_in canvas⟩ show approve.tsx --wait --data ⟨string '{"plan":"deploy"}'⟩ | jq -r .decision
    """

    static let swift = """
    ⟨keyword let⟩ panel = ⟨title CanvasPanel⟩(contentRect: frame)
    panel.level = .⟨variable floating⟩
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    """

    static let json = """
    { ⟨attr "event"⟩: ⟨string "result"⟩, ⟨attr "value"⟩: { ⟨attr "decision"⟩: ⟨string "approve"⟩ } }
    """

    static func cell(_ value: String) -> [[String: Any]] { value.isEmpty ? [] : [run(value)] }

    static func task(_ done: Bool, _ value: String) -> [String: Any] {
        ["task": true, "checked": done, "blocks": [para([run(value)])]]
    }

    static var table: [String: Any] {
        let rows = [
            ["Live reload", "✓", "✓", "Watches the file, even atomic saves"],
            ["Highlighting", "✓", "✓", "Shiki, GitHub light and dark"],
            ["Results", "", "✓", ""], ["Buttons footer", "✓", "✓", ""]
        ]
        return ["t": "table", "align": [NSNull(), "center", "center", NSNull()],
                "head": ["Feature", "Markdown", "TSX", "Notes"].map(cell),
                "rows": rows.map { $0.map(cell) }]
    }

    static var blocks: [[String: Any]] {
        [
            heading(1, "Hello, Canvas"),
            para([run("Canvas renders Markdown and TSX in a floating panel. Agents call "), code("canvas show plan.md"),
                  run(", and the panel updates live as the file changes."), ["t": "fnref", "id": "live", "n": 1]]),
            ["t": "quote", "blocks": [
                para([run("Keep it calm. Generous whitespace, one accent color, and nothing that shouts.")])
            ]],
            heading(2, "What renders"), table,
            heading(2, "Today"),
            ["t": "list", "ordered": false, "items": [
                task(true, "Build the panel server"),
                task(true, "Render Markdown with tables, footnotes and task lists"),
                task(false, "Ship the shortcut cheat sheet"), task(false, "Mermaid diagrams, later")
            ]],
            heading(2, "Code"),
            fence("ts", typescript), fence("bash", bash), fence("swift", swift), fence("json", json),
            ["t": "hr"],
            para([run("Links open in your default browser: "),
                  ["t": "link", "href": "https://shiki.style", "inl": [run("shiki.style")]],
                  run(". Press Esc to close.")]),
            ["t": "footnotes", "items": [
                ["id": "live", "blocks": [para([run("Editors that save by replacing the file are handled too.")])]]
            ]]
        ]
    }

    static var element: Element { node("Markdown", ["blocks": blocks]) }
}
