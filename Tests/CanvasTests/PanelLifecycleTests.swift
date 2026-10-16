import CanvasCore
import CoreGraphics
import Foundation
import Testing

/// The sequence the panel controller runs: a `show` restores or places, the
/// user drags, a later `show` or `move` merges, and `list` reports.
@Suite struct PanelLifecycleTests {
    private let store = FrameStore(url: temporaryDirectory().appendingPathComponent("frames.json"))
    private let desktop = Desktop(screens: Screens.all, mouse: CGPoint(x: 700, y: 400))
    private let visible = Screens.laptop.visibleFrame

    /// What `PanelController.start` does with a `show` request.
    private func open(_ fields: [String: Any], content: CGFloat = 400) throws -> (PanelLayout, CGRect) {
        let request = try showRequest(fields)
        var layout = PanelLayout(placement: request.placement)
        layout.contentHeight = content
        layout.remembered = store.restore(id: request.id, placement: request.placement, screens: desktop.screens)
        let placed = layout.place(in: desktop)
        return (layout, try #require(placed))
    }

    @Test func aDraggedPanelReopensWhereTheUserLeftIt() throws {
        var (layout, frame) = try open(["id": "notes"])
        #expect(frame == CGRect(x: 396, y: 272, width: 720, height: 400))
        let dragged = CGRect(x: 1000, y: 60, width: 480, height: 400)
        layout.userMoved(.drag, to: dragged, in: visible)
        store.remember(id: "notes", frame: dragged, screens: desktop.screens)

        let (_, reopened) = try open(["id": "notes"], content: 600)
        #expect(reopened == CGRect(x: 1000, y: 60, width: 480, height: 600))
        let (_, positioned) = try open(["id": "notes", "position": "top"])
        #expect(positioned == CGRect(x: 396, y: 480, width: 720, height: 400))
        let (_, forgotten) = try open(["id": "notes", "forget": true])
        #expect(forgotten == frame)
        let (_, again) = try open(["id": "notes"])
        #expect(again == frame)
    }

    @Test func replacingContentKeepsThePanelWhereItIs() throws {
        var (layout, frame) = try open(["position": "top-right", "width": 320], content: 180)
        let change = layout.apply(try showRequest(["title": "New"]).placement)
        #expect(change == .none && layout.placement.position == .topRight && layout.placement.width == .points(320))
        #expect(layout.resize(frame, in: visible) == frame)
    }

    @Test func moveToAPresetAndThenResizeAroundItsAnchor() throws {
        var (layout, _) = try open([:], content: 300)
        #expect(layout.apply(try placement(#"{"position":"bottom-right"}"#)) == .place)
        let placed = layout.place(in: desktop)
        let moved = try #require(placed)
        #expect(moved == CGRect(x: 768, y: 24, width: 720, height: 300))
        #expect(layout.apply(try placement(#"{"width":"50%"}"#)) == .resize)
        #expect(layout.resize(moved, in: visible) == CGRect(x: 732, y: 24, width: 756, height: 300))
    }

    @Test(arguments: [
        (#"{"pin":true,"level":"normal"}"#, #"{"clickThrough":false,"level":"floating","pinned":true,"stack":null}"#),
        (#"{"pin":true,"level":"top","clickThrough":true}"#,
         #"{"clickThrough":true,"level":"top","pinned":true,"stack":null}"#),
        (#"{"level":"normal","stack":"notes"}"#,
         #"{"clickThrough":false,"level":"normal","pinned":false,"stack":"notes"}"#)
    ])
    func listingReportsHowTheWindowBehaves(request: String, expected: String) throws {
        #expect(canonical(try placement(request).listing) == expected)
    }

    @Test func framesGoOnTheWireInWholePoints() {
        let frame = CGRect(x: -2560.5, y: 20.6, width: 300.5, height: 199.49)
        #expect(frame.wire == ["x": -2561, "y": 21, "width": 301, "height": 199])
    }
}
