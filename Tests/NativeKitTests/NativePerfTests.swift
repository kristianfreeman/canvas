import AppKit
@testable import CanvasApp
import CanvasCore
import Foundation
import Testing

/// Offscreen layout timings, printed as `native-perf:` lines. The ceilings
/// are loose: they catch a regression of an order of magnitude, not noise.
@Suite(.serialized) @MainActor struct NativePerfTests {
    static func milliseconds(_ runs: Int, _ body: () throws -> Void) rethrows -> Double {
        var samples: [Double] = []
        for _ in 0..<runs {
            let start = ContinuousClock.now
            try body()
            let elapsed = ContinuousClock.now - start
            let parts = elapsed.components
            samples.append(Double(parts.attoseconds) / 1e15 + Double(parts.seconds) * 1000)
        }
        return samples.sorted()[samples.count / 2]
    }

    static func report(_ name: String, cold: Double, warm: Double) {
        print(String(format: "native-perf: %@ cold %.1f ms, warm %.2f ms", name, cold, warm))
    }

    static var bigTable: Element {
        let rows = (0..<40).map { index in
            ["service-\(index)", "v1.\(index).0", index.isMultiple(of: 3) ? "maya" : "kristian", "\(index)m 12s"]
        }
        let columns: [[String: Any]] = [["key": "a"], ["key": "b"], ["key": "c"], ["key": "d", "align": "right"]]
        return node("Table", ["columns": columns],
                    children: [.slot("head", ["Service", "Version", "Author", "Duration"].map {
                        node("TableCell", [:], text($0))
                    })] + rows.enumerated().map { index, row in
                        node("TableRow", ["key": index], children: row.map { node("TableCell", [:], text($0)) })
                    })
    }

    /// A top.tsx-sized panel: twelve stat cards with 120-point sparklines and a table.
    static var bigTree: [Element] {
        let cards = (0..<12).map { index in
            node("Card", ["padding": 14], node("Stack", ["gap": 8],
                 node("Stat", [:], slot("label", text("Core \(index)")), slot("value", text("\(index * 7)%"))),
                 node("Sparkline", ["data": (0..<120).map { Double(($0 * 37 + index) % 100) }, "width": "100%",
                                    "height": 28, "color": "accent"])))
        }
        return [node("Stack", ["gap": 12], node("Grid", ["columns": 3, "gap": 12], children: cards), bigTable)]
    }

    func measure(_ name: String,
                 _ elements: [Element],
                 change: (ViewTree) throws -> Void) throws -> (cold: Double, warm: Double) {
        let built = try tree(elements)
        var fresh = try (0..<5).map { _ in try tree(elements) }
        let cold = Self.milliseconds(5) {
            _ = NativeLayout.fittingHeight(root: fresh.removeLast().root, width: Render.width,
                                           theme: Theme(mode: .dark))
        }
        let measurer = NativeMeasurer(surface: NativeSurface(root: built.root))
        _ = measurer.height(width: Render.width)
        let warm = try Self.milliseconds(20) {
            try change(built)
            _ = measurer.height(width: Render.width)
        }
        Self.report(name, cold: cold, warm: warm)
        return (cold, warm)
    }

    @Test func tableOfFortyRows() throws {
        var flip = false
        let (cold, warm) = try measure("table 40x4", [Self.bigTable]) { tree in
            flip.toggle()
            let cell = tree.root.children[0].body[7].children[1].children[0]
            try tree.apply([["op": "setText", "id": cell.id, "text": flip ? "v9.9.99-long" : "v1.7.0"]])
        }
        #expect(cold < 1000 && warm < 250)
    }

    @Test func helloMarkdown() throws {
        var flip = false
        let (cold, warm) = try measure("hello.md", [HelloBlocks.element]) { tree in
            flip.toggle()
            let extra = flip ? [HelloBlocks.para([HelloBlocks.run("One more line.")])] : []
            let blocks = HelloBlocks.blocks + extra
            try tree.apply([["op": "props", "id": tree.root.children[0].id, "props": ["blocks": blocks]]])
        }
        #expect(cold < 1000 && warm < 250)
    }

    @Test func sparklineUpdateInABigTree() throws {
        var tick = 0
        var rendered: Set<Int> = []
        KitProbe.onBody = { rendered.insert($0) }
        defer { KitProbe.onBody = nil }
        let (cold, warm) = try measure("sparkline update, 12 cards + table", Self.bigTree) { tree in
            tick += 1
            let spark = tree.root.children[0].children[0].children[4].children[0].children[1]
            rendered = []
            try tree.apply([["op": "props", "id": spark.id, "props": [
                "data": (0..<120).map { Double(($0 * 13 + tick) % 100) }, "width": "100%", "height": 28,
                "color": "accent"
            ]]])
        }
        #expect(rendered.count == 1, "re-rendered \(rendered)")
        #expect(cold < 1500 && warm < 250)
    }
}
