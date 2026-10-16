@testable import CanvasApp
import CanvasCore
import Foundation
import Testing

/// Table rows and headers: selection tint, sort arrows, clicks.
@Suite(.serialized) @MainActor struct NativeTableTests {
    static func table(rows: [[String]], head: [[String: Any]], rowProps: [[String: Any]] = []) -> Element {
        let columns: [[String: Any]] = [["key": "name"], ["key": "pid", "align": "right"]]
        let header = zip(["Name", "PID"], head).map { label, props in node("TableCell", props, text(label)) }
        let body = rows.enumerated().map { index, row in
            node("TableRow", ["key": "\(index)"].merging(index < rowProps.count ? rowProps[index] : [:]) { $1 },
                 children: row.map { node("TableCell", [:], text($0)) })
        }
        return node("Table", ["columns": columns], children: [.slot("head", header)] + body)
    }

    static let rows = [["launchd", "1"], ["WindowServer", "812"]]

    static func pixels(_ element: Element) throws -> Pixels {
        try #require(Render.image(try tree(element), mode: .dark).flatMap(Pixels.init))
    }

    /// The distinct colors down one column of pixels.
    static func column(_ pixels: Pixels, x: Int) -> [[Int]] {
        (0..<pixels.height).reduce(into: []) { colors, y in
            let color = Array(pixels.pixel(x, y).prefix(3))
            if colors.last != color { colors.append(color) }
        }
    }

    /// Accent #0a84ff at 12% over the dark background #0a0a0a.
    static let tint = [10, 25, 39]

    static func near(_ colors: [[Int]], _ target: [Int]) -> Bool {
        colors.contains { color in zip(color, target).allSatisfy { abs($0 - $1) <= 2 } }
    }

    @Test func selectedRowIsTinted() throws {
        let plain = try Self.pixels(Self.table(rows: Self.rows, head: [[:], [:]]))
        let selected = try Self.pixels(Self.table(rows: Self.rows, head: [[:], [:]],
                                                  rowProps: [[:], ["selected": true]]))
        let x = selected.width / 2
        #expect(!Self.near(Self.column(plain, x: x), Self.tint))
        #expect(Self.near(Self.column(selected, x: x), Self.tint), "\(Self.column(selected, x: x))")
    }

    /// While sorted, an unsorted right-aligned header keeps a hidden arrow's
    /// width, so its label sits left of the column's right edge.
    @Test func unsortedHeadersReserveTheArrow() throws {
        let content = Int(PanelHeader.height) * 2
        let unsorted = InkBands(try Self.pixels(Self.table(rows: Self.rows, head: [[:], [:]])), from: content).bands
        let sorted = InkBands(try Self.pixels(Self.table(rows: Self.rows, head: [["sort": "descending"], [:]])),
                              from: content).bands
        try #require(unsorted.count == 3 && sorted.count == 3)
        #expect(abs(unsorted[0].last - unsorted[1].last) <= 2, "\(unsorted.map(\.last))")
        #expect(sorted[1].last - sorted[0].last >= 14, "\(sorted.map(\.last))")
    }

    /// A clickable sorted header is drawn in `fg`, brighter than a muted one.
    @Test func sortedClickableHeaderIsLit() throws {
        let content = Int(PanelHeader.height) * 2
        func brightest(_ head: [[String: Any]]) throws -> Int {
            let pixels = try Self.pixels(Self.table(rows: Self.rows, head: head))
            let band = try #require(InkBands(pixels, from: content).bands.first)
            return (band.first...band.first + 60).flatMap { x in
                (content..<content + 60).map { pixels.pixel(x, $0).prefix(3).reduce(0, +) }
            }.max() ?? 0
        }
        let muted = try brightest([["onClick": ["$fn": 1]], [:]])
        let lit = try brightest([["onClick": ["$fn": 1], "sort": "ascending"], [:]])
        #expect(muted < 520 && lit > 650, "muted \(muted), lit \(lit)")
    }

    @Test func rowAndHeaderClicksInvokeWithNoArguments() throws {
        let tree = try tree(Self.table(rows: Self.rows, head: [["onClick": ["$fn": 3]], [:]],
                                       rowProps: [["onClick": ["$fn": 5]], [:]]))
        let events = RecordingEvents()
        let actions = KitActions(events: events, fields: nil)
        for node in tree.root.subtree where node.type == "TableRow" || node.type == "TableCell" { actions.click(node) }
        #expect(events.invoked.map(\.fn) == [3, 5])
        #expect(events.invoked.allSatisfy { $0.args.isEmpty })
    }

    @Test func sortDirectionAndRowFill() {
        let theme = Theme(mode: .light)
        #expect(SortDirection.descending.arrow == "↓" && SortDirection.ascending.arrow == "↑")
        #expect(TableRowFill.fill(theme: theme, hovered: true, selected: true) == theme.tokens.cardHover)
        #expect(TableRowFill.fill(theme: theme, hovered: false, selected: true) == theme.accent.opacity(0.12))
        #expect(TableRowFill.fill(theme: theme, hovered: false, selected: false) == nil)
    }
}
