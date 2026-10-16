import CanvasCore
import CoreGraphics
import Testing

@Suite struct StackingTests {
    private let visible = Screens.laptop.visibleFrame

    /// 360 wide in the top-right corner: x = 1512 - 24 - 360 = 1128, top
    /// edge 944 - 24 = 920.
    private func topRightHome(_ height: CGFloat) -> CGRect {
        CGRect(x: 1128, y: 920 - height, width: 360, height: height)
    }

    @Test func topAnchoredStackGrowsDownward() {
        let frames = Stacking.frames(homes: [100, 150, 80].map(topRightHome), anchor: .top, in: visible)
        #expect(frames == [
            CGRect(x: 1128, y: 820, width: 360, height: 100),
            CGRect(x: 1128, y: 658, width: 360, height: 150),
            CGRect(x: 1128, y: 566, width: 360, height: 80)
        ])
    }

    @Test func reflowsWhenOneCloses() {
        let frames = Stacking.frames(homes: [100, 80].map(topRightHome), anchor: .top, in: visible)
        #expect(frames == [
            CGRect(x: 1128, y: 820, width: 360, height: 100),
            CGRect(x: 1128, y: 728, width: 360, height: 80)
        ])
    }

    @Test func bottomAnchoredStackGrowsUpward() {
        let homes = [100, 150].map { CGRect(x: 1128, y: 24, width: 360, height: $0) }
        #expect(Stacking.frames(homes: homes, anchor: .bottom, in: visible) == [
            CGRect(x: 1128, y: 24, width: 360, height: 100),
            CGRect(x: 1128, y: 136, width: 360, height: 150)
        ])
    }

    @Test func centeredStackGrowsDownFromTheFirst() {
        let homes = [CGRect(x: 396, y: 372, width: 720, height: 200), CGRect(x: 456, y: 422, width: 600, height: 100)]
        #expect(Stacking.frames(homes: homes, anchor: .center, in: visible) == [
            CGRect(x: 396, y: 372, width: 720, height: 200),
            CGRect(x: 456, y: 260, width: 600, height: 100)
        ])
    }

    @Test func overflowStopsAtTheVisibleEdge() {
        let frames = Stacking.frames(homes: Array(repeating: topRightHome(300), count: 5), anchor: .top, in: visible)
        #expect(frames == [
            CGRect(x: 1128, y: 620, width: 360, height: 300),
            CGRect(x: 1128, y: 308, width: 360, height: 300),
            CGRect(x: 1128, y: 0, width: 360, height: 300),
            CGRect(x: 1128, y: 0, width: 360, height: 300),
            CGRect(x: 1128, y: 0, width: 360, height: 300)
        ])
    }

    @Test func bottomOverflowStopsAtTheTop() {
        let homes = Array(repeating: CGRect(x: 24, y: 24, width: 360, height: 400), count: 3)
        #expect(Stacking.frames(homes: homes, anchor: .bottom, in: visible) == [
            CGRect(x: 24, y: 24, width: 360, height: 400),
            CGRect(x: 24, y: 436, width: 360, height: 400),
            CGRect(x: 24, y: 544, width: 360, height: 400)
        ])
    }

    @Test func emptyGroupHasNoFrames() {
        #expect(Stacking.frames(homes: [], anchor: .top, in: visible).isEmpty)
    }

    /// Seeded groups of 1 to 8 panels in a right-hand corner. Every slot is
    /// on screen. While the group fits (24 + the heights + 12 per gap is at
    /// most the visible height), neighbours are exactly 12 pt apart and no
    /// two overlap; past that, slots rest against the far edge.
    @Test(arguments: 0..<1000)
    func slotsStayOnScreenAndApartWhileTheyFit(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        let screen = Screens.all.randomElement(using: &rng)?.visibleFrame ?? visible
        let anchor: Anchor.Vertical = Bool.random(using: &rng) ? .top : .bottom
        let count = Int.random(in: 1...8, using: &rng)
        let heights = (0..<count).map { _ in CGFloat(Int.random(in: 40...500, using: &rng)) }
        let homes = heights.map { height in
            CGRect(x: screen.maxX - 384, y: anchor == .top ? screen.maxY - 24 - height : screen.minY + 24,
                   width: 360, height: height)
        }
        let frames = Stacking.frames(homes: homes, anchor: anchor, in: screen)
        #expect(frames.count == homes.count && frames.allSatisfy { contains(screen, $0) })
        var used: CGFloat = 24 - Stacking.gap
        for (index, frame) in frames.enumerated() {
            used += heights[index] + Stacking.gap
            guard used <= screen.height else {
                #expect(anchor == .top ? frame.minY == screen.minY : frame.maxY == screen.maxY, "seed \(seed)")
                continue
            }
            #expect(frames[..<index].allSatisfy { !$0.intersects(frame) }, "seed \(seed)")
            guard index > 0 else { continue }
            let gap = anchor == .top ? frames[index - 1].minY - frame.maxY : frame.minY - frames[index - 1].maxY
            #expect(gap == Stacking.gap, "seed \(seed)")
        }
    }
}
