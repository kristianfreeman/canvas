import AppKit
import CanvasCore

/// Lays out and draws a sample panel that uses every kit type once,
/// offscreen and never in a window, so the first real panel doesn't pay
/// SwiftUI's one-time costs: view metadata, fonts, text layout and the
/// controls' AppKit backing.
enum NativePrewarm {
    /// Returns the milliseconds it took.
    @discardableResult
    static func run(width: CGFloat = PanelLayout.defaultWidth) -> Double {
        let start = Clock.now()
        let tree = ViewTree()
        do {
            try tree.apply(PrewarmSample.ops)
        } catch {
            debugLog("prewarm sample failed: \(error)")
        }
        for mode in ThemeMode.allCases {
            let surface = NativeSurface(root: tree.root, title: "Canvas", theme: Theme(mode: mode))
            MainActor.assumeIsolated { lay(surface, width: width) }
        }
        return Clock.milliseconds(from: start, to: Clock.now())
    }

    @MainActor
    private static func lay(_ surface: NativeSurface, width: CGFloat) {
        let view = NativeHostingView(rootView: NativePanelView(surface: surface))
        view.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
    }
}

/// Host elements as nested values, written out as the ops a commit sends.
indirect enum PrewarmElement {
    case node(String, [String: Any], [Self])
    case text(String)
    case slot(String, [Self])

    static func of(_ type: String, _ props: [String: Any], _ children: Self...) -> Self {
        .node(type, props, children)
    }

    static func of(_ type: String) -> Self {
        .node(type, [:], [])
    }

    static func ops(_ elements: [Self]) -> [[String: Any]] {
        let writer = Writer()
        for element in elements { writer.write(element, parent: 0) }
        return writer.ops
    }

    private final class Writer {
        var ops: [[String: Any]] = []
        private var next = 1

        func write(_ element: PrewarmElement, parent: Int) {
            let id = next
            next += 1
            switch element {
            case .text(let value):
                ops.append(["op": "text", "id": id, "text": value])
            case .node(let type, let props, let children):
                ops.append(["op": "create", "id": id, "type": type, "props": props])
                for child in children { write(child, parent: id) }
            case .slot(let name, let children):
                ops.append(["op": "create", "id": id, "type": ViewNode.slotType, "props": ["name": name]])
                for child in children { write(child, parent: id) }
            }
            ops.append(["op": "append", "parent": parent, "child": id])
        }
    }
}
