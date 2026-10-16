import Combine
import Foundation

/// One host element or text node from the native runtime. SwiftUI views
/// observe it; `ViewTree.apply` is the only writer.
public final class ViewNode: ObservableObject, Identifiable {
    public let id: Int
    public let type: String
    @Published public internal(set) var props: [String: JSONValue]
    @Published public internal(set) var text: String?
    @Published public internal(set) var children: [ViewNode] = []
    public internal(set) weak var parent: ViewNode?

    public static let textType = "#text"
    public static let slotType = "slot"

    init(id: Int, type: String, props: [String: JSONValue] = [:], text: String? = nil) {
        self.id = id
        self.type = type
        self.props = props
        self.text = text
    }

    public var isText: Bool { type == Self.textType }

    /// The children of the `slot` named `name`, or nil when there is none.
    public func slot(_ name: String) -> [ViewNode]? {
        children.first { $0.type == Self.slotType && $0.props["name"]?.string == name }?.children
    }

    /// Children that aren't slots.
    public var body: [ViewNode] { children.filter { $0.type != Self.slotType } }

    /// All text under this node, in order.
    public var textContent: String {
        isText ? (text ?? "") : children.map(\.textContent).joined()
    }
}

public enum ViewTreeError: Error, Equatable, CustomStringConvertible {
    case malformed(String)
    case unknownNode(Int)
    case duplicateNode(Int)
    case notAChild(parent: Int, child: Int)
    case cycle(Int)

    public var description: String {
        switch self {
        case .malformed(let op): "malformed op: \(op)"
        case .unknownNode(let id): "unknown node \(id)"
        case .duplicateNode(let id): "node \(id) already exists"
        case .notAChild(let parent, let child): "node \(child) is not a child of \(parent)"
        case .cycle(let id): "node \(id) would contain itself"
        }
    }
}

/// The node table for one panel. The root container is node 0.
public final class ViewTree {
    public let root = ViewNode(id: 0, type: "root")
    private var nodes: [Int: ViewNode] = [:]

    public init() {
        nodes[0] = root
    }

    public var count: Int { nodes.count - 1 }

    public func node(_ id: Int) -> ViewNode? { nodes[id] }

    /// Applies one commit. Nodes detached and not re-attached by the end of
    /// the batch are dropped, with their subtrees.
    public func apply(_ ops: [[String: Any]]) throws {
        var detached: Set<Int> = []
        for op in ops {
            try apply(op, detached: &detached)
        }
        for id in detached {
            if let node = nodes[id], node.parent == nil { drop(node) }
        }
    }

    private func apply(_ op: [String: Any], detached: inout Set<Int>) throws {
        let name = op["op"] as? String
        switch name {
        case "create", "text": try create(op)
        case "append", "insert": try attach(op, detached: &detached)
        case "remove": try detach(op, detached: &detached)
        case "props": try node(op, "id").props = Self.props(op["props"])
        case "setText": try node(op, "id").text = op["text"] as? String ?? ""
        default: throw ViewTreeError.malformed(name ?? "?")
        }
    }

    private func create(_ op: [String: Any]) throws {
        let id = try Self.id(op, "id")
        guard id != 0, nodes[id] == nil else { throw ViewTreeError.duplicateNode(id) }
        if op["op"] as? String == "text" {
            nodes[id] = ViewNode(id: id, type: ViewNode.textType, text: op["text"] as? String ?? "")
        } else {
            guard let type = op["type"] as? String else { throw ViewTreeError.malformed("create") }
            nodes[id] = ViewNode(id: id, type: type, props: Self.props(op["props"]))
        }
    }

    private func attach(_ op: [String: Any], detached: inout Set<Int>) throws {
        let parent = try node(op, "parent")
        let child = try node(op, "child")
        guard child !== root, !isAncestor(child, of: parent) else { throw ViewTreeError.cycle(child.id) }
        let before = op["before"] == nil ? nil : try node(op, "before")
        if let before, before === child || before.parent !== parent {
            throw ViewTreeError.notAChild(parent: parent.id, child: before.id)
        }
        if let old = child.parent { old.children.removeAll { $0 === child } }
        var children = parent.children
        if let before, let index = children.firstIndex(where: { $0 === before }) {
            children.insert(child, at: index)
        } else {
            children.append(child)
        }
        parent.children = children
        child.parent = parent
        detached.remove(child.id)
    }

    private func detach(_ op: [String: Any], detached: inout Set<Int>) throws {
        let parent = try node(op, "parent")
        let child = try node(op, "child")
        guard child.parent === parent else { throw ViewTreeError.notAChild(parent: parent.id, child: child.id) }
        parent.children.removeAll { $0 === child }
        child.parent = nil
        detached.insert(child.id)
    }

    private func isAncestor(_ candidate: ViewNode, of node: ViewNode) -> Bool {
        var current: ViewNode? = node
        while let here = current {
            if here === candidate { return true }
            current = here.parent
        }
        return false
    }

    private func drop(_ node: ViewNode) {
        for child in node.children { drop(child) }
        nodes[node.id] = nil
    }

    private func node(_ op: [String: Any], _ key: String) throws -> ViewNode {
        let id = try Self.id(op, key)
        guard let node = nodes[id] else { throw ViewTreeError.unknownNode(id) }
        return node
    }

    private static func id(_ op: [String: Any], _ key: String) throws -> Int {
        guard let number = op[key] as? NSNumber else { throw ViewTreeError.malformed("missing \(key)") }
        return number.intValue
    }

    private static func props(_ any: Any?) -> [String: JSONValue] {
        (any as? [String: Any])?.mapValues(JSONValue.init) ?? [:]
    }
}
