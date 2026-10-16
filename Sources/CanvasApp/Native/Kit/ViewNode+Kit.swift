import CanvasCore
import Combine

extension ViewNode {
    /// The `slot` node named `name`, which views observe for its children.
    func slotNode(_ name: String) -> ViewNode? {
        children.first { $0.type == Self.slotType && $0.props["name"]?.string == name }
    }

    func prop(_ key: String) -> JSONValue? { props[key] }

    /// This node and everything under it, depth first.
    var subtree: [ViewNode] { [self] + children.flatMap(\.subtree) }

    /// The closest ancestor of `type`, or nil.
    func ancestor(_ type: String) -> ViewNode? {
        var current = parent
        while let node = current {
            if node.type == type { return node }
            current = node.parent
        }
        return nil
    }

    /// Fires when any of `nodes` or their descendants changes.
    static func changes(_ nodes: [ViewNode]) -> Publishers.MergeMany<ObservableObjectPublisher> {
        Publishers.MergeMany(nodes.flatMap(\.subtree).map(\.objectWillChange))
    }
}
