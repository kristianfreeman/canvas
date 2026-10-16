import CanvasCore
import CoreGraphics
import Testing

/// The recipes in docs/positioning.md, with each command's request as the
/// CLI sends it and the frame it lands at on the test displays.
@Suite struct PositioningRecipeTests {
    private func place(_ request: String, content: CGFloat, mouse: CGPoint) throws -> (PanelLayout, CGRect?) {
        var layout = PanelLayout(placement: try placement(request))
        layout.contentHeight = content
        let frame = layout.place(in: Desktop(screens: Screens.all, mouse: mouse))
        return (layout, frame)
    }

    /// canvas show cpu.tsx --id cpu --screen main --position top-right --width 320 --pin --click-through
    ///   --opacity 0.85
    @Test func pinnedHUDInTheTopRightOfTheMainDisplay() throws {
        let request = """
            {"screen":"main","position":"top-right","pin":true,"clickThrough":true,"opacity":0.85,"width":320}
            """
        let (layout, frame) = try place(request, content: 180, mouse: CGPoint(x: -1000, y: 500))
        #expect(frame == CGRect(x: 1168, y: 740, width: 320, height: 180))
        #expect(layout.screen == Screens.laptop)
        #expect(layout.anchor == Anchor(.top, .right))
        let hud = layout.placement
        #expect(hud.effectiveLevel == .floating && hud.effectiveSpaces == .all && !hud.closesOnEscape)
        #expect(hud.clickThrough && hud.opacity == 0.85)
    }

    /// canvas toggle keys.tsx --id cheatsheet --position center --width 880 --data - < keys.json
    @Test func centeredCheatSheet() throws {
        let (layout, frame) = try place(#"{"position":"center","width":880}"#, content: 600,
                                        mouse: CGPoint(x: 700, y: 400))
        #expect(frame == CGRect(x: 316, y: 172, width: 880, height: 600))
        #expect(!layout.placement.restoresRememberedFrame)
        #expect(try placement(#"{"width":880}"#).restoresRememberedFrame)
    }

    /// canvas show examples/approve.tsx --position mouse --width 420 --wait
    @Test func approvalAtTheMouse() throws {
        let (layout, frame) = try place(#"{"position":"mouse","width":420}"#, content: 300,
                                        mouse: CGPoint(x: 1000, y: 600))
        #expect(frame == CGRect(x: 1012, y: 288, width: 420, height: 300))
        #expect(layout.anchor == Anchor(.top, .left))
    }

    /// canvas show examples/dashboard.tsx --screen 2 --position right --margin 0 --width 50% --height 100%,
    /// and the same with --screen dell, or with --at -0,0 for the position.
    @Test(arguments: [
        #"{"screen":"2","position":"right","margin":0,"width":"50%","height":"100%"}"#,
        #"{"screen":"dell","position":"right","margin":0,"width":"50%","height":"100%"}"#,
        #"{"screen":"2","at":{"x":"-0","y":"0"},"width":"50%","height":"100%"}"#
    ])
    func dashboardFillingTheRightHalfOfTheSecondDisplay(request: String) throws {
        let (layout, frame) = try place(request, content: 300, mouse: CGPoint(x: 700, y: 400))
        #expect(frame == CGRect(x: -1280, y: 0, width: 1280, height: 1415))
        #expect(layout.screen == Screens.external)
    }

    /// echo '…' | canvas show - --id note-N --stack notes --position top-right --width 360, three times,
    /// then canvas hide --id note-2
    @Test func stackedNotifications() throws {
        let request = #"{"stack":"notes","position":"top-right","width":360}"#
        let mouse = CGPoint(x: 700, y: 400)
        let notes = try [100, 150, 80].map { try place(request, content: $0, mouse: mouse).0 }
        #expect(PanelLayout.stackedFrames(notes, on: Screens.laptop, mouse: mouse) == [
            CGRect(x: 1128, y: 820, width: 360, height: 100),
            CGRect(x: 1128, y: 658, width: 360, height: 150),
            CGRect(x: 1128, y: 566, width: 360, height: 80)
        ])
        #expect(PanelLayout.stackedFrames([notes[0], notes[2]], on: Screens.laptop, mouse: mouse) == [
            CGRect(x: 1128, y: 820, width: 360, height: 100),
            CGRect(x: 1128, y: 728, width: 360, height: 80)
        ])
    }

    /// canvas move --id cpu --position bottom-right
    @Test func moveTheHUDToTheBottomRight() throws {
        let mouse = CGPoint(x: 700, y: 400)
        var hud = try place(#"{"screen":"main","position":"top-right","pin":true,"width":320}"#,
                            content: 180, mouse: mouse).0
        #expect(hud.apply(try placement(#"{"position":"bottom-right"}"#)) == .place)
        let moved = hud.place(in: Desktop(screens: Screens.all, mouse: mouse))
        #expect(moved == CGRect(x: 1168, y: 24, width: 320, height: 180))
        #expect(hud.placement.pin && hud.anchor == Anchor(.bottom, .right))
    }

    /// canvas move --id cheatsheet --width 50%: 756 wide around the old
    /// center line x = 756.
    @Test func moveWidensAroundTheCenter() throws {
        let (layout, frame) = try place(#"{"position":"center","width":880}"#, content: 600,
                                        mouse: CGPoint(x: 700, y: 400))
        var sheet = layout
        #expect(sheet.apply(try placement(#"{"width":"50%"}"#)) == .resize)
        let placed = try #require(frame)
        let widened = sheet.resize(placed, in: Screens.laptop.visibleFrame)
        #expect(widened == CGRect(x: 378, y: 172, width: 756, height: 600))
    }
}
