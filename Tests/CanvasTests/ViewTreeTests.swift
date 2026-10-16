import CanvasCore
import Testing

@Suite struct ViewTreeTests {
    private static func create(_ id: Int, _ type: String = "Stack", _ props: [String: Any] = [:]) -> [String: Any] {
        ["op": "create", "id": id, "type": type, "props": props]
    }

    private static func append(_ parent: Int, _ child: Int) -> [String: Any] {
        ["op": "append", "parent": parent, "child": child]
    }

    private static func remove(_ parent: Int, _ child: Int) -> [String: Any] {
        ["op": "remove", "parent": parent, "child": child]
    }

    private static func ids(_ node: ViewNode?) -> [Int] {
        node?.children.map(\.id) ?? []
    }

    /// Root holds 1 (Card) with children 2, 3, 4; 5 is a text child of 2.
    private static func sample() throws -> ViewTree {
        let tree = ViewTree()
        try tree.apply([
            create(1, "Card", ["padding": 16]), create(2), create(3), create(4),
            ["op": "text", "id": 5, "text": "hi"],
            append(2, 5), append(1, 2), append(1, 3), append(1, 4), append(0, 1)
        ])
        return tree
    }

    @Test func createAndTextMakeTypedNodes() throws {
        let tree = try Self.sample()
        #expect(tree.count == 5)
        #expect(tree.node(1)?.type == "Card")
        #expect(tree.node(1)?.props["padding"] == .number(16))
        #expect(tree.node(5)?.isText == true)
        #expect(tree.node(5)?.text == "hi")
        #expect(tree.node(5)?.parent === tree.node(2))
        #expect(Self.ids(tree.root) == [1])
    }

    @Test func insertPlacesTheChildBeforeItsSibling() throws {
        let tree = try Self.sample()
        try tree.apply([Self.create(6), ["op": "insert", "parent": 1, "child": 6, "before": 3]])
        #expect(Self.ids(tree.node(1)) == [2, 6, 3, 4])
    }

    @Test func insertMovesAnExistingChildWithinItsParent() throws {
        let tree = try Self.sample()
        try tree.apply([["op": "insert", "parent": 1, "child": 4, "before": 2]])
        #expect(Self.ids(tree.node(1)) == [4, 2, 3])
    }

    @Test func appendMovesANodeBetweenParentsWithItsSubtree() throws {
        let tree = try Self.sample()
        try tree.apply([Self.append(3, 2)])
        #expect(Self.ids(tree.node(1)) == [3, 4])
        #expect(Self.ids(tree.node(3)) == [2])
        #expect(tree.node(2)?.parent === tree.node(3))
        #expect(tree.node(5)?.text == "hi")
        #expect(tree.count == 5)
    }

    @Test func removedThenReaddedInTheSameBatchSurvives() throws {
        let tree = try Self.sample()
        try tree.apply([Self.remove(1, 2), Self.append(4, 2)])
        #expect(Self.ids(tree.node(4)) == [2])
        #expect(tree.node(5) != nil)
        #expect(tree.count == 5)
    }

    @Test func removedAndNotReaddedIsDroppedWithItsSubtree() throws {
        let tree = try Self.sample()
        try tree.apply([Self.remove(1, 2)])
        #expect(tree.node(2) == nil)
        #expect(tree.node(5) == nil)
        #expect(tree.count == 3)
        #expect(Self.ids(tree.node(1)) == [3, 4])
    }

    @Test func aChildMovedOutBeforeItsParentIsDroppedSurvives() throws {
        let tree = try Self.sample()
        try tree.apply([Self.remove(0, 1), Self.append(0, 3)])
        #expect(tree.node(1) == nil)
        #expect(tree.node(2) == nil)
        #expect(tree.node(4) == nil)
        #expect(tree.node(3)?.parent === tree.root)
        #expect(tree.count == 1)
    }

    @Test func aNodeReattachedInsideADroppedSubtreeIsDropped() throws {
        let tree = try Self.sample()
        try tree.apply([Self.remove(1, 3), Self.append(2, 3), Self.remove(1, 2)])
        #expect(tree.node(3) == nil)
        #expect(tree.node(2) == nil)
        #expect(Self.ids(tree.node(1)) == [4])
    }

    @Test func propsReplacesTheWholeSet() throws {
        let tree = try Self.sample()
        try tree.apply([["op": "props", "id": 1, "props": ["title": "x", "onClick": ["$fn": 3]]]])
        #expect(tree.node(1)?.props == ["title": .string("x"), "onClick": .function(3)])
    }

    @Test func setTextChangesTheText() throws {
        let tree = try Self.sample()
        try tree.apply([["op": "setText", "id": 5, "text": "bye"]])
        #expect(tree.root.textContent == "bye")
    }
}

@Suite struct ViewTreeErrorTests {
    private static func tree() throws -> ViewTree {
        let tree = ViewTree()
        try tree.apply([
            ["op": "create", "id": 1, "type": "Stack", "props": [:]],
            ["op": "create", "id": 2, "type": "Stack", "props": [:]],
            ["op": "append", "parent": 1, "child": 2],
            ["op": "append", "parent": 0, "child": 1]
        ])
        return tree
    }

    private static func failure(_ op: [String: Any]) throws -> ViewTreeError? {
        do {
            try tree().apply([op])
            return nil
        } catch let error as ViewTreeError {
            return error
        }
    }

    @Test func unknownNodes() throws {
        #expect(try Self.failure(["op": "append", "parent": 1, "child": 9]) == .unknownNode(9))
        #expect(try Self.failure(["op": "append", "parent": 9, "child": 2]) == .unknownNode(9))
        #expect(try Self.failure(["op": "props", "id": 9, "props": [:]]) == .unknownNode(9))
        #expect(try Self.failure(["op": "setText", "id": 9, "text": ""]) == .unknownNode(9))
    }

    @Test func duplicateIds() throws {
        #expect(try Self.failure(["op": "create", "id": 2, "type": "Text", "props": [:]]) == .duplicateNode(2))
        #expect(try Self.failure(["op": "text", "id": 1, "text": "x"]) == .duplicateNode(1))
        #expect(try Self.failure(["op": "create", "id": 0, "type": "Text", "props": [:]]) == .duplicateNode(0))
    }

    @Test func cycles() throws {
        #expect(try Self.failure(["op": "append", "parent": 2, "child": 1]) == .cycle(1))
        #expect(try Self.failure(["op": "append", "parent": 1, "child": 1]) == .cycle(1))
        #expect(try Self.failure(["op": "append", "parent": 2, "child": 0]) == .cycle(0))
    }

    @Test func removingOrInsertingBeforeANonChild() throws {
        #expect(try Self.failure(["op": "remove", "parent": 0, "child": 2]) == .notAChild(parent: 0, child: 2))
        #expect(try Self.failure(["op": "insert", "parent": 0, "child": 2, "before": 2])
            == .notAChild(parent: 0, child: 2))
    }

    @Test func aFailedInsertLeavesTheChildWhereItWas() throws {
        let tree = try Self.tree()
        #expect(throws: ViewTreeError.notAChild(parent: 0, child: 2)) {
            try tree.apply([["op": "insert", "parent": 0, "child": 2, "before": 2]])
        }
        #expect(tree.node(1)?.children.map(\.id) == [2])
        #expect(tree.node(2)?.parent === tree.node(1))
    }

    @Test func malformedOps() throws {
        #expect(try Self.failure(["op": "move", "id": 1]) == .malformed("move"))
        #expect(try Self.failure(["op": "append", "child": 1]) == .malformed("missing parent"))
        #expect(try Self.failure(["op": "create", "id": 3]) == .malformed("create"))
    }
}
