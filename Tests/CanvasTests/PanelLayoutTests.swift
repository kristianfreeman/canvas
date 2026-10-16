import CanvasCore
import CoreGraphics
import Testing

@Suite struct PanelLayoutTests {
    private let visible = Screens.laptop.visibleFrame
    private let onLaptop = Desktop(screens: Screens.all, mouse: CGPoint(x: 700, y: 400))

    /// Dragged to (100, 500, 500, 300): top edge 800, right edge 600.
    private func remembered(_ anchor: Anchor, x: CGFloat = 100) -> RememberedFrame {
        RememberedFrame(frame: CGRect(x: x, y: 500, width: 500, height: 300), anchor: anchor)
    }

    private func layout(_ request: String, content: CGFloat?) throws -> PanelLayout {
        var layout = PanelLayout(placement: try placement(request))
        layout.contentHeight = content
        return layout
    }

    @Test(arguments: [
        (#"{"position":"top-right","width":320}"#, CGRect(x: 1168, y: 620, width: 320, height: 300)),
        (#"{"position":"bottom-right","width":320}"#, CGRect(x: 1168, y: 24, width: 320, height: 300)),
        (#"{"position":"right","width":320}"#, CGRect(x: 1168, y: 322, width: 320, height: 300)),
        (#"{"at":{"x":100,"y":"-10%"},"width":320}"#, CGRect(x: 100, y: 94, width: 320, height: 300)),
        (#"{"at":{"x":-100,"y":100},"width":320}"#, CGRect(x: 1092, y: 544, width: 320, height: 300))
    ])
    func growsAwayFromTheAnchoredEdge(request: String, grown: CGRect) throws {
        var panel = try layout(request, content: 180)
        let frame = panel.place(in: onLaptop)
        let placed = try #require(frame)
        #expect(placed.size == CGSize(width: 320, height: 180))
        panel.contentHeight = 300
        #expect(panel.resize(placed, in: visible) == grown)
    }

    @Test func growthPastTheEdgeShiftsAndShrinkingReturns() throws {
        var panel = try layout(#"{"position":"top-left","maxHeight":"100%"}"#, content: 300)
        let frame = panel.place(in: onLaptop)
        let placed = try #require(frame)
        #expect(placed == CGRect(x: 24, y: 620, width: 720, height: 300))
        panel.contentHeight = 944
        let tall = panel.resize(placed, in: visible)
        #expect(tall == CGRect(x: 24, y: 0, width: 720, height: 944))
        panel.contentHeight = 300
        #expect(panel.resize(tall, in: visible) == placed)
    }

    @Test func aMovedWindowReanchorsWhereItIs() throws {
        var panel = try layout(#"{"position":"top-left"}"#, content: 300)
        _ = panel.place(in: onLaptop)
        panel.contentHeight = 500
        #expect(panel.resize(CGRect(x: 300, y: 300, width: 720, height: 300), in: visible)
            == CGRect(x: 300, y: 100, width: 720, height: 500))
        #expect(panel.anchor == Anchor(.top, .left))
    }

    @Test func userDragKeepsWidthAndAnchorsToNearerEdges() throws {
        var panel = try layout("{}", content: 400)
        _ = panel.place(in: onLaptop)
        let dragged = CGRect(x: 1000, y: 100, width: 400, height: 300)
        panel.userMoved(.drag, to: dragged, in: visible)
        #expect(panel.anchor == Anchor(.bottom, .right))
        panel.contentHeight = 500
        #expect(panel.resize(dragged, in: visible) == CGRect(x: 1000, y: 100, width: 400, height: 500))
    }

    @Test func aDragLeavesTheStackAndAResizeDoesNot() throws {
        var panel = try layout(#"{"stack":"notes","width":320}"#, content: 200)
        _ = panel.place(in: onLaptop)
        let moved = CGRect(x: 900, y: 300, width: 320, height: 200)
        #expect(panel.userMoved(.resize, to: moved, in: visible) == nil)
        #expect(panel.placement.stack == "notes" && !panel.placement.restoresRememberedFrame)
        #expect(panel.userMoved(.drag, to: moved, in: visible) == "notes")
        #expect(panel.placement.stack == nil, "a dragged panel stayed in its stack")
        #expect(panel.placement.restoresRememberedFrame, "a dragged-out panel won't reopen where it was dropped")
        #expect(panel.userMoved(.drag, to: moved, in: visible) == nil, "a second drag left the stack again")
        #expect(panel.apply(try placement(#"{"stack":"notes"}"#)) == .place)
        #expect(panel.placement.stack == "notes")
    }

    @Test func applyMergesAndSaysWhatToDo() throws {
        var panel = try layout(#"{"position":"top-right","pin":true}"#, content: 300)
        panel.userWidth = 500
        #expect(panel.apply(try placement(#"{"opacity":0.5}"#)) == .none)
        #expect(panel.placement.position == .topRight && panel.placement.pin && panel.placement.opacity == 0.5)
        #expect(panel.userWidth == 500)
        #expect(panel.apply(try placement(#"{"width":400}"#)) == .resize)
        #expect(panel.userWidth == nil)
        #expect(panel.apply(try placement(#"{"screen":"main"}"#)) == .place)
        #expect(panel.apply(try placement(#"{"position":"left"}"#)) == .place)
        #expect(panel.placement.position == .left && panel.placement.pin)
    }

    @Test func positionDropsAnOlderAt() throws {
        let base = try placement(#"{"at":{"x":10,"y":10},"opacity":0.5}"#)
        let moved = base.merging(try placement(#"{"position":"bottom"}"#))
        #expect(moved.at == nil && !moved.given.contains(.at) && moved.position == .bottom)
        #expect(moved.opacity == 0.5 && moved.given == [.position, .opacity])
        let again = moved.merging(try placement(#"{"at":{"x":-5,"y":-5}}"#))
        #expect(again.at == AtPoint(x: .points(-5), y: .points(-5)) && again.presetAnchor == Anchor(.bottom, .right))
    }

    @Test(arguments: [
        ("{}", Placement.Change.none), (#"{"opacity":0.2,"pin":true,"level":"top"}"#, .none),
        (#"{"height":300}"#, .resize), (#"{"maxHeight":"50%"}"#, .resize), (#"{"margin":0}"#, .place),
        (#"{"stack":"a"}"#, .place), (#"{"at":{"x":0,"y":0},"width":10}"#, .place), (#"{"forget":true}"#, .place)
    ])
    func changeFollowsTheGivenFields(request: String, expected: Placement.Change) throws {
        #expect(Placement.change(for: try placement(request)) == expected)
    }

    @Test func restoresTheRememberedEdgeAndWidth() throws {
        var panel = try layout("{}", content: 200)
        panel.remembered = remembered(Anchor(.top, .left))
        #expect(panel.place(in: onLaptop) == CGRect(x: 100, y: 600, width: 500, height: 200))
        #expect(panel.anchor == Anchor(.top, .left) && panel.userWidth == 500)
    }

    @Test func explicitWidthBeatsTheRememberedOne() throws {
        var panel = try layout(#"{"width":300}"#, content: 200)
        panel.remembered = remembered(Anchor(.top, .right))
        #expect(panel.place(in: onLaptop) == CGRect(x: 300, y: 600, width: 300, height: 200))
    }

    @Test func rememberedFrameYieldsToAnExplicitOtherScreen() throws {
        var elsewhere = try layout(#"{"screen":"2"}"#, content: 400)
        elsewhere.remembered = remembered(Anchor(.top, .left))
        #expect(elsewhere.place(in: onLaptop) == CGRect(x: -1640, y: 507, width: 720, height: 400))
        var same = try layout(#"{"screen":"1"}"#, content: 400)
        same.remembered = remembered(Anchor(.top, .left))
        #expect(same.place(in: onLaptop) == CGRect(x: 100, y: 400, width: 500, height: 400))
    }

    @Test func rememberedFrameOnAMissingScreenIsIgnored() throws {
        var panel = try layout("{}", content: 400)
        panel.remembered = remembered(Anchor(.top, .left), x: 9000)
        #expect(panel.place(in: onLaptop) == CGRect(x: 396, y: 272, width: 720, height: 400))
    }

    @Test func noScreensPlaceNothing() throws {
        var panel = try layout("{}", content: 400)
        #expect(panel.place(in: Desktop(screens: [], mouse: .zero)) == nil)
    }
}
