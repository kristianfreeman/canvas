import AppKit
@testable import CanvasApp
import CanvasCore
import Foundation
import SwiftUI
import Testing

@Suite(.serialized) @MainActor struct NativeLayoutTests {
    static func texts(_ count: Int) -> Element {
        node("Stack", ["gap": 12], children: (0..<count).map { node("Text", [:], text("Line \($0)")) })
    }

    @Test func fittingHeightGrowsWithContent() throws {
        let heights = try [0, 1, 2, 4].map { Render.height(try tree(Self.texts($0))) }
        #expect(heights[0] >= PanelHeader.height + 30, "\(heights)")
        #expect(heights[0] < heights[1] && heights[1] < heights[2] && heights[2] < heights[3], "\(heights)")
        let step = heights[2] - heights[1]
        #expect(abs((heights[3] - heights[2]) - 2 * step) < 1, "\(heights)")
        let wrapped = try tree(node("Text", [:], text(String(repeating: "wrapping words ", count: 40))))
        #expect(Render.height(wrapped, width: 300) > Render.height(wrapped, width: 900) + 40)
    }

    /// Thirty text nodes in one Text wrap as one paragraph, not thirty rows.
    @Test func textRunsFlowAsOneText() throws {
        let words = Array(repeating: "word ", count: 30)
        let split = try tree(node("Text", [:], children: words.map(text)))
        let joined = try tree(node("Text", [:], text(words.joined())))
        #expect(Render.height(split) == Render.height(joined))
        let mixed = try tree(node("Text", [:], text("run "), node("Code", [:], text("code")), text(" after")))
        let single = try tree(node("Text", [:], text("one line")))
        #expect(abs(Render.height(mixed) - Render.height(single)) < 1)
    }

    @Test func slotsRender() throws {
        let bare = try tree(node("Card", [:], text("body")))
        let titled = try tree(node("Card", [:], slot("title", text("CPU")), text("body")))
        let full = try tree(node("Card", [:], slot("title", text("CPU")), slot("subtitle", text("all cores")),
                                 slot("actions", node("Badge", [:], text("ok"))), text("body")))
        #expect(Render.height(titled) > Render.height(bare) + 12)
        #expect(Render.height(full) > Render.height(titled) + 10)
        let stat = try tree(node("Stat", [:], slot("label", text("Load")), slot("value", text("42"))))
        let hinted = try tree(node("Stat", [:], slot("label", text("Load")), slot("value", text("42")),
                                   slot("hint", text("last minute"))))
        #expect(Render.height(hinted) > Render.height(stat) + 12)
    }

    @Test func unknownTypesRenderNothing() throws {
        let plain = try tree(node("Stack", [:], node("Text", [:], text("a")), node("Text", [:], text("b"))))
        let mystery = try tree(node("Stack", [:], node("Text", [:], text("a")),
                                    node("Mystery", ["x": 1], node("Text", [:], text("hidden"))),
                                    node("Text", [:], text("b"))))
        #expect(Render.height(mystery) == Render.height(plain))
        let empty = try tree()
        #expect(Render.height(try tree(node("div", [:], text("dom")))) == Render.height(empty))
        #expect(Render.image(mystery, mode: .dark) != nil)
    }

    /// The left column starts at the content edge, the second column's left
    /// edge and the right-aligned column's right edge line up in every row.
    @Test func tableAlignsColumns() throws {
        let rows = [["A", "B", "C"], ["x", "beta", "1"], ["much longer text", "b", "123456"]]
        let table = node("Table", ["columns": [["key": "a"], ["key": "b"], ["key": "c", "align": "right"]]],
                         children: [.slot("head", rows[0].map { node("TableCell", [:], text($0)) })]
                            + rows.dropFirst().enumerated().map { index, row in
                                node("TableRow", ["key": index], children: row.map { node("TableCell", [:], text($0)) })
                            })
        let pixels = try #require(Render.image(try tree(table), mode: .dark).flatMap(Pixels.init))
        let bands = InkBands(pixels, from: Int(PanelHeader.height) * 2).bands
        try #require(bands.count == 3, "\(bands.count) text rows")
        let content = Int(NativeRootView.padding.leading) * 2
        for band in bands {
            #expect(abs(band.first - content) <= 3, "left edge \(band.first)")
            #expect(abs(band.last - bands[0].last) <= 2, "right edges \(bands.map(\.last))")
            #expect(abs(band.second - bands[0].second) <= 2, "second column \(bands.map(\.second))")
        }
        #expect(bands[0].last > pixels.width - content - 8)
    }

    @Test func propsChangeRerendersOnlyThatNode() throws {
        let tree = try tree(node("Stack", [:], node("Text", [:], text("a")),
                                 node("Card", [:], node("Sparkline", ["data": [1, 2, 3]])),
                                 node("Text", [:], text("b"))))
        let host = Hosted(tree)
        var seen: [Int] = []
        KitProbe.onBody = { seen.append($0) }
        defer { KitProbe.onBody = nil }
        host.settle()
        #expect(seen.isEmpty, "a settled view re-rendered \(seen)")
        let spark = try #require(tree.root.children.first?.children[1].children.first)
        try tree.apply([["op": "props", "id": spark.id, "props": ["data": [3, 2, 1], "color": "green"]]])
        host.settle()
        #expect(Set(seen) == [spark.id], "re-rendered \(seen)")
        seen = []
        let label = try #require(tree.root.children.first?.children.first?.children.first)
        try tree.apply([["op": "setText", "id": label.id, "text": "changed"]])
        host.settle()
        #expect(!seen.contains(spark.id) && !seen.contains(tree.root.children.first?.id ?? -1), "\(seen)")
    }

    /// A hosted panel redraws in place when its surface's theme or accent changes.
    @Test func themeAndAccentChangesRedraw() throws {
        let surface = NativeSurface(root: try tree(node("Progress", ["value": 1, "color": "accent"])).root)
        let host = Hosted(surface)
        let near = { (colors: [[Int]], target: [Int]) in
            colors.contains { color in zip(color, target).allSatisfy { abs($0 - $1) <= 3 } }
        }
        let dark = try host.column()
        #expect(near(dark, [10, 10, 10]) && near(dark, [10, 132, 255]), "\(dark)")
        surface.theme = Theme(mode: .light, accent: "#ff2d55")
        host.settle()
        let light = try host.column()
        #expect(near(light, [255, 255, 255]) && near(light, [255, 45, 85]), "\(light)")
        #expect(!near(light, [10, 132, 255]), "\(light)")
    }

    @Test func measurerFollowsTreeUpdates() throws {
        let tree = try tree(Self.texts(1))
        let measurer = NativeMeasurer(surface: NativeSurface(root: tree.root))
        let before = measurer.height(width: Render.width)
        let added = OpWriter([node("Text", [:], text("more"))], firstID: 100).ops.map { op in
            op["parent"] as? Int == 0 ? op.merging(["parent": tree.root.children[0].id]) { $1 } : op
        }
        try tree.apply(added)
        #expect(measurer.height(width: Render.width) > before + 10)
    }
}

/// A panel in an `NSHostingView` that is never put in a window.
@MainActor
final class Hosted {
    let view: NSHostingView<NativePanelView>

    convenience init(_ tree: ViewTree) {
        self.init(NativeSurface(root: tree.root))
    }

    init(_ surface: NativeSurface) {
        view = NSHostingView(rootView: NativePanelView(surface: surface, scrolls: false, controls: .still))
        view.frame = CGRect(x: 0, y: 0, width: Render.width, height: 600)
        settle()
    }

    /// The distinct colors down the middle of the view, drawn without a window.
    func column() throws -> [[Int]] {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let pixels = try #require(rep.cgImage.flatMap(Pixels.init))
        return (0..<pixels.height).reduce(into: []) { colors, y in
            let color = Array(pixels.pixel(pixels.width / 2, y).prefix(3))
            if colors.last != color { colors.append(color) }
        }
    }

    func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        view.layoutSubtreeIfNeeded()
        _ = view.fittingSize
    }
}

/// Horizontal bands of light pixels (text on the dark theme) and where the
/// ink in each starts, where its second run starts and where it ends.
struct InkBands {
    struct Band {
        let first: Int
        let second: Int
        let last: Int
    }

    let bands: [Band]

    init(_ pixels: Pixels, from top: Int) {
        var masks: [[Bool]] = []
        var current: [Bool]?
        for y in top..<pixels.height {
            let row = (0..<pixels.width).map { x in
                let start = (y * pixels.width + x) * 4
                return Int(pixels.bytes[start]) + Int(pixels.bytes[start + 1]) + Int(pixels.bytes[start + 2]) > 300
            }
            if row.contains(true) {
                current = current.map { zip($0, row).map { $0 || $1 } } ?? row
            } else if let band = current {
                masks.append(band)
                current = nil
            }
        }
        if let current { masks.append(current) }
        bands = masks.map { mask in
            let xs = mask.indices.filter { mask[$0] }
            let gap = zip(xs, xs.dropFirst()).first { $1 - $0 > 40 }
            return Band(first: xs[0], second: gap?.1 ?? xs[0], last: xs[xs.count - 1])
        }
    }
}
