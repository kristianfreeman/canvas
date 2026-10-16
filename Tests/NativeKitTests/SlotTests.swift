import CanvasCore
import Testing

@Suite struct SlotTests {
    @Test func slotsAreSeparateFromTheBody() throws {
        let tree = ViewTree()
        try tree.apply([
            ["op": "create", "id": 1, "type": "Card", "props": [:]],
            ["op": "create", "id": 2, "type": "slot", "props": ["name": "title"]],
            ["op": "text", "id": 3, "text": "CPU"],
            ["op": "text", "id": 4, "text": "body"],
            ["op": "append", "parent": 2, "child": 3],
            ["op": "append", "parent": 1, "child": 2],
            ["op": "append", "parent": 1, "child": 4],
            ["op": "append", "parent": 0, "child": 1]
        ])
        let card = try #require(tree.node(1))
        #expect(card.slot("title")?.first?.text == "CPU")
        #expect(card.body.map(\.textContent) == ["body"])
        #expect(card.slot("subtitle") == nil)
    }
}
