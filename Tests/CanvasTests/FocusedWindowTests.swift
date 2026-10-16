import CanvasCore
import CoreGraphics
import Foundation
import Testing

/// `--screen focused` from window-list entries, on the laptop with the
/// external display to its left and the portrait one above.
@Suite struct FocusedWindowTests {
    private let appPID: Int32 = 501
    private let mainHeight = Screens.laptop.frame.height

    /// A window-list entry: bounds in window-list coordinates (y down from
    /// the top of the main screen).
    private func window(pid: Int32, _ bounds: CGRect, layer: Int = 0, alpha: Double = 1) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowBounds as String: ["X": bounds.minX, "Y": bounds.minY,
                                        "Width": bounds.width, "Height": bounds.height] as NSDictionary
        ]
    }

    @Test func flipsWindowListCoordinatesIntoAppKit() {
        let rect = FocusedWindow.appKitRect(fromWindowList: CGRect(x: 100, y: 50, width: 800, height: 600),
                                            mainScreenHeight: mainHeight)
        #expect(rect == CGRect(x: 100, y: 332, width: 800, height: 600))
        let above = FocusedWindow.appKitRect(fromWindowList: CGRect(x: 300, y: -1500, width: 600, height: 400),
                                             mainScreenHeight: mainHeight)
        #expect(above == CGRect(x: 300, y: 2082, width: 600, height: 400))
    }

    @Test func picksTheAppsFrontmostOrdinaryWindow() {
        let windows = [
            window(pid: 77, CGRect(x: 0, y: 0, width: 1512, height: 38)),
            window(pid: appPID, CGRect(x: 1200, y: 0, width: 30, height: 24), layer: 25),
            window(pid: appPID, CGRect(x: 10, y: 10, width: 500, height: 500), alpha: 0),
            window(pid: appPID, CGRect(x: 40, y: 40, width: 0, height: 300)),
            window(pid: appPID, CGRect(x: -2000, y: 100, width: 900, height: 700)),
            window(pid: appPID, CGRect(x: 100, y: 100, width: 800, height: 600))
        ]
        let frame = FocusedWindow.frame(of: appPID, in: windows, mainScreenHeight: mainHeight)
        #expect(frame == CGRect(x: -2000, y: 182, width: 900, height: 700))
    }

    @Test func noWindowOfTheAppIsNil() {
        let windows = [window(pid: 77, CGRect(x: 0, y: 0, width: 400, height: 300)), [:]]
        #expect(FocusedWindow.frame(of: appPID, in: windows, mainScreenHeight: mainHeight) == nil)
    }

    @Test func focusedSelectsTheDisplayHoldingMostOfTheWindow() {
        let straddling = window(pid: appPID, CGRect(x: -300, y: 200, width: 1000, height: 500))
        let frame = FocusedWindow.frame(of: appPID, in: [straddling], mainScreenHeight: mainHeight)
        let mouseOnExternal = CGPoint(x: -1000, y: 500)
        let desktop = Desktop(screens: Screens.all, mouse: mouseOnExternal, focusedWindow: frame)
        #expect(desktop.screen(for: .focused) == Screens.laptop)
        let none = Desktop(screens: Screens.all, mouse: mouseOnExternal, focusedWindow: nil)
        #expect(none.screen(for: .focused) == Screens.external)
    }
}
