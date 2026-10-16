import CanvasCore
import Testing

@Suite struct ViewTreeOpsTests {
    @Test func createAppendAndRemove() throws {
        let tree = ViewTree()
        try tree.apply([
            ["op": "create", "id": 1, "type": "Card", "props": ["padding": 16]],
            ["op": "text", "id": 2, "text": "hi"],
            ["op": "append", "parent": 1, "child": 2],
            ["op": "append", "parent": 0, "child": 1]
        ])
        #expect(tree.root.children.first?.type == "Card")
        #expect(tree.root.textContent == "hi")
        try tree.apply([["op": "remove", "parent": 0, "child": 1]])
        #expect(tree.root.children.isEmpty)
        #expect(tree.node(2) == nil)
    }
}
