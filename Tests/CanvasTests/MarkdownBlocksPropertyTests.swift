import CanvasCore
import Foundation
import Testing

/// Seeded random block trees, encoded the way the runtime sends them and
/// decoded back. Each property runs 300 seeds; a failure names its seed.
@Suite struct MarkdownBlocksPropertyTests {
    struct Generator {
        var rng: SeededRNG

        mutating func pick(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &rng) }

        mutating func word() -> String { ["a", "Hello", "", "✓", "`x`", "<b>", "a b"][pick(0...6)] }

        mutating func inlines(depth: Int) -> [MarkdownInline] {
            (0..<pick(0...4)).map { _ in inline(depth: depth) }
        }

        mutating func inline(depth: Int) -> MarkdownInline {
            switch pick(0...(depth > 0 ? 4 : 3)) {
            case 0: .text(word(), TextMarks(rawValue: pick(0...7)))
            case 1: .code(word())
            case 2: .lineBreak
            case 3: .footnoteRef(id: word(), number: pick(1...9))
            default: .link(href: "https://x.y/" + word(), inlines(depth: depth - 1))
            }
        }

        mutating func blocks(depth: Int) -> [MarkdownBlock] {
            (0..<pick(0...3)).map { _ in depth > 0 && pick(0...1) == 0 ? container(depth: depth) : leaf() }
        }

        mutating func leaf() -> MarkdownBlock {
            switch pick(0...3) {
            case 0: .heading(level: pick(1...6), inlines(depth: 1))
            case 1: .paragraph(inlines(depth: 2))
            case 2: .rule
            default: .code(lang: pick(0...1) == 0 ? nil : "ts", lines: (0..<pick(0...3)).map { _ in
                [CodeToken(word(), scope: pick(0...1) == 0 ? nil : "string")]
            })
            }
        }

        mutating func container(depth: Int) -> MarkdownBlock {
            switch pick(0...2) {
            case 0: .quote(blocks(depth: depth - 1))
            case 1: .list(MarkdownList(ordered: pick(0...1) == 1, start: pick(0...5),
                                       items: (0..<pick(0...3)).map { _ in item(depth: depth) }))
            default: .footnotes([MarkdownFootnote(id: word(), blocks: blocks(depth: depth - 1))])
            }
        }

        mutating func item(depth: Int) -> MarkdownListItem {
            let task = pick(0...1) == 1
            return MarkdownListItem(task: task, checked: task && pick(0...1) == 1, blocks: blocks(depth: depth - 1))
        }
    }

    @Test(arguments: 0..<300)
    func encodedTreesDecodeBack(seed: UInt64) throws {
        var generator = Generator(rng: SeededRNG(seed: seed))
        let tree = generator.blocks(depth: 3) + [.table(MarkdownTable(
            align: [.left, nil, .center], head: [generator.inlines(depth: 1)], rows: [[generator.inlines(depth: 1)]]))]
        let encoded = try JSONSerialization.data(withJSONObject: tree.map(MarkdownJSON.block))
        let decoded = MarkdownBlocks.decode(JSONValue(try JSONSerialization.jsonObject(with: encoded)))
        #expect(decoded == tree, "seed \(seed)")
    }
}

/// The runtime's encoding, written out independently of the decoder.
enum MarkdownJSON {
    static func block(_ block: MarkdownBlock) -> [String: Any] {
        switch block {
        case .heading(let level, let inl): ["t": "h", "level": level, "inl": inl.map(inline)]
        case .paragraph(let inl): ["t": "p", "inl": inl.map(inline)]
        case .quote(let blocks): ["t": "quote", "blocks": blocks.map(self.block)]
        case .list(let list): ["t": "list", "ordered": list.ordered, "start": list.start, "items": list.items.map(item)]
        case .code(let lang, let lines): ["t": "code", "lang": lang ?? "", "lines": lines.map { $0.map(token) }]
        default: leaf(block)
        }
    }

    static func item(_ item: MarkdownListItem) -> [String: Any] {
        ["task": item.task ? true : NSNull(), "checked": item.checked, "blocks": item.blocks.map(block)]
    }

    static func leaf(_ block: MarkdownBlock) -> [String: Any] {
        switch block {
        case .table(let table): ["t": "table", "align": table.align.map { $0?.rawValue ?? NSNull() as Any },
                                 "head": table.head.map { $0.map(inline) },
                                 "rows": table.rows.map { $0.map { $0.map(inline) } }]
        case .footnotes(let items): ["t": "footnotes", "items": items.map {
            ["id": $0.id, "blocks": $0.blocks.map(Self.block)] as [String: Any]
        }]
        default: ["t": "hr"]
        }
    }

    static func token(_ token: CodeToken) -> [String: Any] {
        token.scope.map { ["s": token.text, "c": $0] } ?? ["s": token.text]
    }

    static func inline(_ inline: MarkdownInline) -> [String: Any] {
        switch inline {
        case .text(let text, let marks):
            ["t": "text", "s": text, "b": marks.contains(.bold), "i": marks.contains(.italic),
             "del": marks.contains(.strike)]
        case .code(let text): ["t": "code", "s": text]
        case .link(let href, let inl): ["t": "link", "href": href, "inl": inl.map(self.inline)]
        case .lineBreak: ["t": "br"]
        case .footnoteRef(let id, let number): ["t": "fnref", "id": id, "n": number]
        }
    }
}
