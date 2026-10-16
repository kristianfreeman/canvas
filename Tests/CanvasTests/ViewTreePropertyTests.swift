import CanvasCore
import Testing

/// A plain reference for `ViewTree.apply`: parent and child lists by id.
private struct ModelTree {
    var parent: [Int: Int] = [:]
    var children: [Int: [Int]] = [0: []]
    var text: [Int: String] = [:]
    var props: [Int: Double] = [:]
    var removed: Set<Int> = []
    var nextId = 1

    var live: [Int] { children.keys.filter { $0 != 0 }.sorted() }

    func isAncestor(_ candidate: Int, of node: Int) -> Bool {
        var current: Int? = node
        while let here = current {
            if here == candidate { return true }
            current = parent[here]
        }
        return false
    }

    mutating func create(isText: Bool) -> Int {
        let id = nextId
        nextId += 1
        children[id] = []
        if isText { text[id] = "t\(id)" } else { props[id] = 0 }
        return id
    }

    mutating func attach(_ child: Int, to parentId: Int, before: Int?) {
        if let old = parent[child] { children[old]?.removeAll { $0 == child } }
        var list = children[parentId] ?? []
        let index = before.flatMap { list.firstIndex(of: $0) } ?? list.count
        list.insert(child, at: index)
        children[parentId] = list
        parent[child] = parentId
        removed.remove(child)
    }

    mutating func detach(_ child: Int) {
        guard let old = parent.removeValue(forKey: child) else { return }
        children[old]?.removeAll { $0 == child }
        removed.insert(child)
    }

    mutating func endBatch() {
        for id in removed where parent[id] == nil && children[id] != nil { drop(id) }
        removed = []
    }

    private mutating func drop(_ id: Int) {
        for child in children[id] ?? [] { drop(child) }
        children[id] = nil
        parent[id] = nil
        text[id] = nil
        props[id] = nil
    }
}

/// Random valid ops against the model, applied to both.
private struct OpGenerator {
    var model = ModelTree()
    var rng: SeededRNG

    private mutating func pick(_ ids: [Int]) -> Int? {
        ids.isEmpty ? nil : ids[Int.random(in: 0..<ids.count, using: &rng)]
    }

    private var containers: [Int] { [0] + model.live.filter { model.text[$0] == nil } }

    private mutating func create() -> [String: Any] {
        let isText = Int.random(in: 0..<3, using: &rng) == 0
        let id = model.create(isText: isText)
        if isText { return ["op": "text", "id": id, "text": "t\(id)"] }
        return ["op": "create", "id": id, "type": "Stack", "props": [:]]
    }

    private mutating func attach() -> [String: Any]? {
        guard let parent = pick(containers),
              let child = pick(model.live.filter { !model.isAncestor($0, of: parent) }) else { return nil }
        let before = Bool.random(using: &rng) ? pick(model.children[parent, default: []].filter { $0 != child }) : nil
        model.attach(child, to: parent, before: before)
        guard let before else { return ["op": "append", "parent": parent, "child": child] }
        return ["op": "insert", "parent": parent, "child": child, "before": before]
    }

    private mutating func remove() -> [String: Any]? {
        guard let child = pick(model.live.filter { model.parent[$0] != nil }), let parent = model.parent[child] else {
            return nil
        }
        model.detach(child)
        return ["op": "remove", "parent": parent, "child": child]
    }

    private mutating func update() -> [String: Any]? {
        guard let id = pick(model.live) else { return nil }
        let value = Double(Int.random(in: 0..<1000, using: &rng))
        if model.text[id] != nil {
            model.text[id] = "s\(value)"
            return ["op": "setText", "id": id, "text": "s\(value)"]
        }
        model.props[id] = value
        return ["op": "props", "id": id, "props": ["n": value]]
    }

    mutating func next() -> [String: Any] {
        switch Int.random(in: 0..<10, using: &rng) {
        case 0..<3: create()
        case 3..<6: attach() ?? create()
        case 6..<8: remove() ?? create()
        default: update() ?? create()
        }
    }
}

@Suite struct ViewTreePropertyTests {
    private static func mismatch(_ node: ViewNode, _ model: ModelTree) -> String? {
        let id = node.id
        let children = node.children.map(\.id)
        if children != model.children[id] { return "children of \(id): \(children) != \(model.children[id] ?? [])" }
        if id == 0 { return nil }
        if node.parent?.id != model.parent[id] { return "parent of \(id)" }
        let same = node.isText ? node.text == model.text[id] : node.props["n"]?.number ?? 0 == model.props[id]
        return same ? nil : "content of \(id)"
    }

    private static func mismatch(_ id: Int, _ node: ViewNode?, _ model: ModelTree) -> String? {
        switch (node, model.children[id] != nil) {
        case (nil, true): "node \(id) missing"
        case (.some, false): "node \(id) should be gone"
        case (let node?, true): mismatch(node, model)
        case (nil, false): nil
        }
    }

    private static func mismatch(_ tree: ViewTree, _ model: ModelTree) -> String? {
        if tree.count != model.live.count { return "count \(tree.count) != \(model.live.count)" }
        return (0..<model.nextId).lazy.compactMap { mismatch($0, tree.node($0), model) }.first
    }

    @Test(arguments: 0..<400)
    func randomBatchesMatchTheReferenceModel(seed: UInt64) throws {
        var generator = OpGenerator(rng: SeededRNG(seed: seed))
        let tree = ViewTree()
        for batch in 0..<10 {
            let count = Int.random(in: 1...14, using: &generator.rng)
            let ops = (0..<count).map { _ in generator.next() }
            try tree.apply(ops)
            generator.model.endBatch()
            if let problem = Self.mismatch(tree, generator.model) {
                Issue.record("seed \(seed), batch \(batch): \(problem)")
                return
            }
        }
    }
}
