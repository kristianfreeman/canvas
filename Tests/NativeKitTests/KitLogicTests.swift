@testable import CanvasApp
import CanvasCore
import CoreGraphics
import Testing

@Suite struct KitLogicTests {
    @Test func gridTracks() {
        #expect(GridTracks.parse(.number(3)) == [.fraction(1), .fraction(1), .fraction(1)])
        #expect(GridTracks.parse(.string("max-content 1fr")) == [.content(max: true), .fraction(1)])
        #expect(GridTracks.parse(.string("1.55fr 1fr")) == [.fraction(1.55), .fraction(1)])
        #expect(GridTracks.parse(.string("120px auto min-content 40")) == [
            .fixed(120), .content(max: true), .content(max: false), .fixed(40)
        ])
        #expect(GridTracks.parse(.string("repeat(2, 1fr 80px) minmax(0, 2fr)")) == [
            .fraction(1), .fixed(80), .fraction(1), .fixed(80), .fraction(2)
        ])
        #expect(GridTracks.parse(nil) == [.fraction(1), .fraction(1)])
        #expect(GridTracks.parse(.string("")) == [.fraction(1), .fraction(1)])
        #expect(GridTracks.parse(.string("bogus")) == [.fraction(1)])
        #expect(GridTracks.parse(.number(1e300)).count == 64)
        #expect(GridTracks.parse(.number(.nan)) == [.fraction(1), .fraction(1)])
    }

    @Test func trackSizingSharesWhatIsLeft() {
        let sizing = TrackSizing(tracks: [.fixed(100), .content(max: true), .fraction(1), .fraction(3)], gap: 10)
        let widths = sizing.widths(available: 530) { column, _ in column == 1 ? 50 : 999 }
        #expect(widths == [100, 50, 87.5, 262.5])
        let ideal = sizing.widths(available: nil) { column, _ in [0, 50, 30, 60][column] }
        #expect(ideal == [100, 50, 30, 90])
    }

    @Test func tableSizingFillsAndShrinks() {
        let sizing = TableSizing(fixed: [nil, 80, nil], widest: [100, 10, 300], narrowest: [40, 10, 60])
        #expect(sizing.widths(available: nil) == [100, 80, 300])
        #expect(sizing.widths(available: 880) == [200, 80, 600])
        let short = sizing.widths(available: 380)
        #expect(short[1] == 80 && abs(short.reduce(0, +) - 380) < 0.001, "\(short)")
        #expect(sizing.widths(available: 10) == [40, 80, 60])
    }

    /// Seeded random columns: a table fills any width it can, never goes
    /// under a column's narrowest, and leaves fixed columns alone.
    @Test(arguments: 0..<300)
    func tableSizingProperties(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        let count = Int.random(in: 1...6, using: &rng)
        let narrowest = (0..<count).map { _ in CGFloat(Int.random(in: 0...80, using: &rng)) }
        let widest = narrowest.map { $0 + CGFloat(Int.random(in: 0...200, using: &rng)) }
        let fixed: [CGFloat?] = (0..<count).map { _ in Int.random(in: 0...3, using: &rng) == 0 ? 50 : nil }
        let available = CGFloat(Int.random(in: 0...1200, using: &rng))
        let widths = TableSizing(fixed: fixed, widest: widest, narrowest: narrowest).widths(available: available)
        let floor = fixed.indices.map { fixed[$0] ?? narrowest[$0] }.reduce(0, +)
        let hasFree = fixed.contains { $0 == nil }
        for index in 0..<count {
            #expect(widths[index] >= (fixed[index] ?? narrowest[index]) - 0.001, "seed \(seed): \(widths)")
            if let width = fixed[index] { #expect(widths[index] == width, "seed \(seed)") }
        }
        if hasFree, available >= floor, widest.contains(where: { $0 > 0 }) || available <= floor {
            #expect(abs(widths.reduce(0, +) - available) < 0.01, "seed \(seed): \(widths) for \(available)")
        }
    }

    @Test func markdownMarginsCollapse() {
        let size: CGFloat = 14.5
        let blocks: [MarkdownBlock] = [.heading(level: 1, []), .paragraph([]), .heading(level: 2, []), .rule, .code(
            lang: nil, lines: [])]
        let gaps = MarkdownMetrics.gaps(blocks.map { MarkdownMetrics.margins($0, scope: .prose, size: size) })
        #expect(gaps[0] == 0)
        #expect(abs(gaps[1] - 0.55 * 23) < 0.001)
        #expect(abs(gaps[2] - 1.7 * 18) < 0.001)
        #expect(abs(gaps[3] - 2 * size) < 0.001)
        #expect(abs(gaps[4] - 2 * size) < 0.001)
        #expect(MarkdownMetrics.margins(.paragraph([]), scope: .item, size: size) == BlockMargins(both: 0))
        #expect(MarkdownMetrics.margins(.paragraph([]), scope: .footnote, size: 13).top == 0.2 * 13)
    }

    @Test func statDeltas() throws {
        let up = try #require(StatDelta(["delta": .string("+12%"), "tone": .string("up"), "good": .bool(true)]))
        #expect(up.text == "▲ 12%" && up.verdict == .good)
        let inverted = try #require(StatDelta(["delta": .string("-38s"), "tone": .string("down"), "good": .bool(true)]))
        #expect(inverted.text == "▼ 38s" && inverted.verdict == .good)
        let bad = try #require(StatDelta(["delta": .number(-1234.5)]))
        #expect(bad.text == "▼ 1,234.5" && bad.verdict == .bad)
        let flat = try #require(StatDelta(["delta": .string("0"), "good": .bool(false)]))
        #expect(flat.text == " 0" && flat.verdict == .neutral)
        #expect(StatDelta([:]) == nil)
        #expect(StatDelta(["delta": .null]) == nil)
    }

    @Test func kitValues() {
        #expect(KitValue.length(.number(12)) == 12)
        #expect(KitValue.length(.string("12px")) == 12)
        #expect(KitValue.length(.string("1em")) == nil)
        #expect(KitValue.length(.number(.infinity)) == nil)
        #expect(KitValue.int(.number(.nan), 3) == 3)
        let style = KitStyle(.object(["padding": .number(4), "paddingTop": .string("10px"), "flex": .number(1)]))
        #expect(style.padding?.top == 10 && style.padding?.leading == 4 && style.fills)
        #expect(KitStyle(nil).isEmpty && KitStyle(.object(["bogus": .number(1)])).isEmpty)
    }
}
