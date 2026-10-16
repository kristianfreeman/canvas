import CanvasCore
import CoreGraphics
import Testing

/// Seeded random screens, placements and page heights. Each property runs
/// 2000 seeds; a failure names its seed.
@Suite struct PlacementPropertyTests {
    static func int(_ range: ClosedRange<Int>, _ rng: inout SeededRNG) -> CGFloat {
        CGFloat(Int.random(in: range, using: &rng))
    }

    static func visible(_ rng: inout SeededRNG) -> CGRect {
        CGRect(x: int(-4000...4000, &rng), y: int(-2500...2500, &rng),
               width: int(120...3000, &rng), height: int(60...2200, &rng))
    }

    static func length(_ rng: inout SeededRNG, signed: Bool) -> Length {
        let negative = signed && Bool.random(using: &rng)
        return Bool.random(using: &rng)
            ? Length(magnitude: int(0...3000, &rng), unit: .points, negative: negative)
            : Length(magnitude: int(0...150, &rng), unit: .percent, negative: negative)
    }

    static func placement(_ rng: inout SeededRNG) -> Placement {
        var placement = Placement()
        placement.position = Placement.Position.allCases.randomElement(using: &rng) ?? .center
        if Int.random(in: 0..<4, using: &rng) == 0 {
            placement.at = AtPoint(x: length(&rng, signed: true), y: length(&rng, signed: true))
        }
        if Bool.random(using: &rng) { placement.margin = int(0...200, &rng) }
        if Bool.random(using: &rng) { placement.width = .points(int(1...4000, &rng)) }
        if Int.random(in: 0..<4, using: &rng) == 0 { placement.height = .points(int(1...3000, &rng)) }
        if Bool.random(using: &rng) { placement.minHeight = .points(int(1...600, &rng)) }
        if Bool.random(using: &rng) { placement.maxHeight = .percent(int(1...150, &rng)) }
        return placement
    }

    static func mouse(near visible: CGRect, _ rng: inout SeededRNG) -> CGPoint {
        CGPoint(x: visible.minX + int(-200...Int(visible.width) + 200, &rng),
                y: visible.minY + int(-200...Int(visible.height) + 200, &rng))
    }

    @Test(arguments: 0..<2000)
    func placedFrameStaysInsideTheVisibleFrame(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        let visible = Self.visible(&rng)
        let placement = Self.placement(&rng)
        let content = CGFloat(Double.random(in: 0...5000, using: &rng))
        let screen = ScreenInfo(frame: visible, visibleFrame: visible)
        let frame = placement.placedFrame(contentHeight: content, on: screen, mouse: Self.mouse(near: visible, &rng))
        #expect(contains(visible, frame), "\(frame) outside \(visible)")
        #expect(frame.width >= min(240, visible.width))
        #expect(frame.height > 0)
    }

    @Test(arguments: 0..<2000)
    func anchoredEdgeSurvivesAnySequenceOfHeights(seed: UInt64) throws {
        var rng = SeededRNG(seed: seed)
        let visible = Self.visible(&rng)
        let first = Self.int(0...3000, &rng)
        var layout = PanelLayout(placement: Self.placement(&rng))
        layout.contentHeight = first
        let desktop = Desktop(screens: [ScreenInfo(frame: visible, visibleFrame: visible)],
                              mouse: Self.mouse(near: visible, &rng))
        let initial = layout.place(in: desktop)
        let placed = try #require(initial)
        let point = layout.anchor.point(of: placed)
        var frame = placed
        for _ in 0..<20 {
            layout.contentHeight = Self.int(0...3000, &rng)
            frame = layout.resize(frame, in: visible)
            #expect(contains(visible, frame) && frame.minX == placed.minX && frame.width == placed.width)
            #expect(layout.anchor.vertical.keeps(frame, at: point.y, in: visible), "seed \(seed)")
        }
        layout.contentHeight = first
        #expect(layout.resize(frame, in: visible) == placed)
    }

    @Test(arguments: 0..<2000)
    func percentLengthsScaleWithTheScreen(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        let small = Self.visible(&rng)
        let large = CGRect(origin: small.origin, size: CGSize(width: small.width * 2, height: small.height * 2))
        let (wide, tall) = (Self.int(1...100, &rng), Self.int(1...100, &rng))
        var placement = Placement()
        placement.width = .percent(wide)
        placement.height = .percent(tall)
        placement.minHeight = .points(1)
        placement.at = AtPoint(x: .percent(Self.int(0...Int(100 - wide), &rng)),
                               y: .percent(Self.int(0...Int(100 - tall), &rng)))
        let (smallScreen, largeScreen) = (ScreenInfo(frame: small, visibleFrame: small),
                                          ScreenInfo(frame: large, visibleFrame: large))
        let one = placement.placedFrame(contentHeight: nil, on: smallScreen, mouse: .zero)
        let two = placement.placedFrame(contentHeight: nil, on: largeScreen, mouse: .zero)
        if one.width > 240 {
            #expect(Self.doubled(one.width, two.width), "seed \(seed)")
            #expect(Self.doubled(one.minX - small.minX, two.minX - large.minX), "seed \(seed)")
        }
        if one.height > 1 {
            #expect(Self.doubled(one.height, two.height), "seed \(seed)")
            #expect(Self.doubled(small.maxY - one.maxY, large.maxY - two.maxY), "seed \(seed)")
        }
    }

    /// `value` is a percentage of twice the extent behind `base`, so it is
    /// 2 × base, or one more when rounding down dropped a half.
    static func doubled(_ base: CGFloat, _ value: CGFloat) -> Bool {
        value == base * 2 || value == base * 2 + 1
    }
}

private extension Anchor.Vertical {
    /// Whether `frame` keeps this edge (or its center line) at `line`, or
    /// rests against a visible edge when it can't fit there.
    func keeps(_ frame: CGRect, at line: CGFloat, in visible: CGRect) -> Bool {
        let height = frame.height
        switch self {
        case .top:
            return line - height >= visible.minY ? frame.maxY == line : frame.minY == visible.minY
        case .bottom:
            return line + height <= visible.maxY ? frame.minY == line : frame.maxY == visible.maxY
        case .center:
            let fits = line - height / 2 >= visible.minY && line + height / 2 <= visible.maxY
            return fits ? abs(frame.midY - line) <= 0.5 : frame.minY == visible.minY || frame.maxY == visible.maxY
        }
    }
}
