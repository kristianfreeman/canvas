import CanvasCore
import Foundation
import Testing

@Suite struct MarkdownBlocksTests {
    static func blocks(_ text: String) -> [MarkdownBlock] {
        MarkdownBlocks.decode(JSONValue(json(text)))
    }

    @Test func everyBlockType() {
        let decoded = Self.blocks("""
        [
          {"t":"h","level":2,"inl":[{"t":"text","s":"Today"}]},
          {"t":"p","inl":[{"t":"text","s":"a","b":true},{"t":"text","s":"b","i":true,"del":true},
            {"t":"code","s":"x"},{"t":"br"},{"t":"link","href":"https://a.b","inl":[{"t":"text","s":"l"}]},
            {"t":"fnref","id":"live","n":1}]},
          {"t":"quote","blocks":[{"t":"p","inl":[{"t":"text","s":"q"}]}]},
          {"t":"list","ordered":true,"start":3,"items":[{"blocks":[]},{"task":true,"checked":true,"blocks":[]}]},
          {"t":"code","lang":"ts","lines":[[{"s":"const","c":"keyword"},{"s":" x"}],[]]},
          {"t":"table","align":["left",null,"right"],"head":[[{"t":"text","s":"A"}],[],[]],
            "rows":[[[{"t":"text","s":"1"}],[],[]]]},
          {"t":"hr"},
          {"t":"footnotes","items":[{"id":"live","blocks":[{"t":"p","inl":[]}]}]}
        ]
        """)
        #expect(decoded == [
            .heading(level: 2, [.text("Today", [])]),
            .paragraph([.text("a", .bold), .text("b", [.italic, .strike]), .code("x"), .lineBreak,
                        .link(href: "https://a.b", [.text("l", [])]), .footnoteRef(id: "live", number: 1)]),
            .quote([.paragraph([.text("q", [])])]),
            .list(MarkdownList(ordered: true, start: 3, items: [
                MarkdownListItem(task: false, checked: false, blocks: []),
                MarkdownListItem(task: true, checked: true, blocks: [])
            ])),
            .code(lang: "ts", lines: [[CodeToken("const", scope: "keyword"), CodeToken(" x")], []]),
            .table(MarkdownTable(align: [.left, nil, .right], head: [[.text("A", [])], [], []],
                                 rows: [[[.text("1", [])], [], []]])),
            .rule,
            .footnotes([MarkdownFootnote(id: "live", blocks: [.paragraph([])])])
        ])
    }

    @Test func malformedInputIsSkippedNotFatal() {
        #expect(MarkdownBlocks.decode(nil).isEmpty)
        #expect(MarkdownBlocks.decode(JSONValue("not blocks")).isEmpty)
        let decoded = Self.blocks("""
        [1, "p", null, {"t":"nope"}, {"inl":[]}, {"t":"p","inl":"oops"},
         {"t":"p","inl":[{"t":"text"},{"t":"mystery","s":"x"},{"t":"text","s":"kept"},7]},
         {"t":"h","level":9}, {"t":"h","level":0,"inl":[]}, {"t":"h","level":"2"},
         {"t":"list","items":[{"task":true}, 3]}, {"t":"code","lang":"","lines":[[{"c":"keyword"},{"s":"ok"}], 5]},
         {"t":"table","rows":[[[{"t":"text","s":"x"}]],[[],[],[]]]}, {"t":"footnotes","items":[{"id":2}]}]
        """)
        #expect(decoded == [
            .paragraph([]),
            .paragraph([.text("kept", [])]),
            .heading(level: 6, []), .heading(level: 1, []), .heading(level: 1, []),
            .list(MarkdownList(ordered: false, start: 1, items: [
                MarkdownListItem(task: true, checked: false, blocks: []),
                MarkdownListItem(task: false, checked: false, blocks: [])
            ])),
            .code(lang: nil, lines: [[CodeToken("ok")], []]),
            .table(MarkdownTable(align: [], head: [], rows: [[[.text("x", [])]], [[], [], []]])),
            .footnotes([MarkdownFootnote(id: "2", blocks: [])])
        ])
        if case .table(let table) = decoded[7] { #expect(table.columnCount == 3) }
    }

    @Test func nonFiniteNumbersDontTrap() {
        let heading = JSONValue.object(["t": .string("h"), "level": .number(.infinity)])
        let list = JSONValue.object(["t": .string("list"), "start": .number(.nan), "items": .array([])])
        let ref = JSONValue.object(["t": .string("fnref"), "id": .number(1e300), "n": .number(-.infinity)])
        #expect(MarkdownBlocks.decode(.array([heading, list])) == [
            .heading(level: 1, []), .list(MarkdownList(ordered: false, start: 1, items: []))
        ])
        #expect(MarkdownBlocks.inlines(.array([ref])) == [.footnoteRef(id: "0", number: 0)])
    }
}
