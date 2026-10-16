import AppKit
@testable import CanvasApp
import CanvasCore
import SwiftUI

/// A host element, text node or slot, written as nested values and turned
/// into the ops a React commit would send.
indirect enum Element {
    case node(String, [String: Any], [Self])
    case text(String)
    case slot(String, [Self])
}

func node(_ type: String) -> Element { .node(type, [:], []) }

func node(_ type: String, _ props: [String: Any], _ children: Element...) -> Element {
    .node(type, props, children)
}

func node(_ type: String, _ props: [String: Any], children: [Element]) -> Element {
    .node(type, props, children)
}

func text(_ value: String) -> Element { .text(value) }

func slot(_ name: String, _ children: Element...) -> Element { .slot(name, children) }

/// Ops for `elements` under the root: creates, then appends bottom up, as
/// React's commit phase does.
final class OpWriter {
    private(set) var ops: [[String: Any]] = []
    private(set) var ids: [Int] = []
    private var next = 1

    init(_ elements: [Element], firstID: Int = 1) {
        next = firstID
        ids = elements.map { write($0, parent: 0) }
    }

    private func write(_ element: Element, parent: Int) -> Int {
        let id = next
        next += 1
        switch element {
        case .text(let value):
            ops.append(["op": "text", "id": id, "text": value])
        case .node(let type, let props, let children):
            ops.append(["op": "create", "id": id, "type": type, "props": props])
            for child in children { _ = write(child, parent: id) }
        case .slot(let name, let children):
            ops.append(["op": "create", "id": id, "type": "slot", "props": ["name": name]])
            for child in children { _ = write(child, parent: id) }
        }
        ops.append(["op": "append", "parent": parent, "child": id])
        return id
    }
}

func tree(_ elements: Element...) throws -> ViewTree {
    try tree(elements)
}

func tree(_ elements: [Element]) throws -> ViewTree {
    let tree = ViewTree()
    try tree.apply(OpWriter(elements).ops)
    return tree
}

/// Records what the kit sends, as a panel's JS bridge would receive it.
final class RecordingEvents: NativeEvents {
    private(set) var invoked: [(fn: Int, args: [Any])] = []
    private(set) var submitted: [Any] = []
    private(set) var opened: [URL] = []
    private(set) var closes = 0

    func invoke(_ fn: Int, _ args: [Any]) { invoked.append((fn, args)) }
    func submit(_ value: Any) { submitted.append(value) }
    func close() { closes += 1 }
    func open(_ url: URL) { opened.append(url) }
}

enum Render {
    static let width: CGFloat = 560

    @MainActor
    static func height(_ tree: ViewTree, mode: ThemeMode = .dark, width: CGFloat = width) -> CGFloat {
        NativeLayout.fittingHeight(root: tree.root, width: width, theme: Theme(mode: mode))
    }

    /// The unscrolled panel drawn offscreen at 2x, controls drawn still.
    @MainActor
    static func image(_ surface: NativeSurface, width: CGFloat = width) -> CGImage? {
        let renderer = ImageRenderer(content: NativePanelView(surface: surface, scrolls: false, controls: .still)
            .frame(width: width))
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return renderer.cgImage
    }

    @MainActor
    static func image(_ tree: ViewTree, mode: ThemeMode, title: String = "") -> CGImage? {
        image(NativeSurface(root: tree.root, title: title, theme: Theme(mode: mode)))
    }
}

/// SplitMix64: a small seeded generator, so failures reproduce from the seed.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
