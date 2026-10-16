import CanvasCore
import CoreGraphics
import Testing

@Suite struct ScreenSelectionTests {
    private func desktop(mouse: CGPoint, focused: CGRect? = nil, screens: [ScreenInfo] = Screens.all) -> Desktop {
        Desktop(screens: screens, mouse: mouse, focusedWindow: focused)
    }

    @Test(arguments: [
        (CGPoint(x: 700, y: 400), "Built-in Retina Display"),
        (CGPoint(x: -1000, y: 1200), "DELL U2723QE"),
        (CGPoint(x: 600, y: 2500), "LG UltraFine"),
        (CGPoint(x: 3000, y: 100), "Built-in Retina Display"),
        (CGPoint(x: -3000, y: 2000), "DELL U2723QE"),
        (CGPoint(x: 700, y: 4000), "LG UltraFine")
    ])
    func mouseSelectsTheScreenUnderOrNearestTheCursor(mouse: CGPoint, expected: String) {
        #expect(desktop(mouse: mouse).screen(for: .mouse)?.name == expected)
    }

    @Test func mainIsTheMenuBarScreenWhateverTheOrder() {
        let reordered = [Screens.external, Screens.portrait, Screens.laptop]
        #expect(desktop(mouse: CGPoint(x: -1000, y: 500), screens: reordered).screen(for: .main) == Screens.laptop)
        let noMain = reordered.map { screen -> ScreenInfo in
            var copy = screen
            copy.isMain = false
            return copy
        }
        #expect(desktop(mouse: .zero, screens: noMain).screen(for: .main)?.name == "DELL U2723QE")
    }

    @Test func focusedIsTheScreenHoldingMostOfTheWindow() {
        let mostlyExternal = CGRect(x: -700, y: 100, width: 1000, height: 600)
        let mouse = CGPoint(x: 600, y: 2500)
        #expect(desktop(mouse: mouse, focused: mostlyExternal).screen(for: .focused) == Screens.external)
        #expect(desktop(mouse: mouse).screen(for: .focused) == Screens.portrait)
        let offScreen = CGRect(x: 5000, y: 5000, width: 100, height: 100)
        #expect(desktop(mouse: mouse, focused: offScreen).screen(for: .focused) == Screens.portrait)
    }

    @Test(arguments: [
        (ScreenSelector.index(1), "Built-in Retina Display"), (.index(2), "DELL U2723QE"), (.index(3), "LG UltraFine"),
        (.index(9), "LG UltraFine"), (.name("dell"), "DELL U2723QE"), (.name("ULTRAFINE"), "LG UltraFine"),
        (.name("built-in"), "Built-in Retina Display"), (.name("Sidecar"), "LG UltraFine")
    ])
    func indexAndNameFallBackToTheMouseScreen(selector: ScreenSelector, expected: String) {
        #expect(desktop(mouse: CGPoint(x: 600, y: 2500)).screen(for: selector)?.name == expected)
    }

    @Test func selectScreenMatchesTheDesktop() {
        let window = CGRect(x: -700, y: 100, width: 1000, height: 600)
        let mouse = CGPoint(x: 600, y: 2500)
        let focused = selectScreen(.focused, screens: Screens.all, mouse: mouse, focusedWindowFrame: window)
        #expect(focused == Screens.external)
        #expect(selectScreen(.focused, screens: Screens.all, mouse: mouse) == Screens.portrait)
        #expect(selectScreen(.main, screens: Screens.all, mouse: mouse) == Screens.laptop)
    }

    @Test func noScreensSelectNothing() {
        #expect(desktop(mouse: .zero, screens: []).screen(for: .main) == nil)
        #expect(desktop(mouse: .zero, screens: []).screen(for: .mouse) == nil)
    }

    @Test func fingerprintIgnoresScreenOrder() {
        let expected = "-2560,0,2560,1440;0,0,1512,982;200,982,1080,1920"
        #expect(Desktop.fingerprint(Screens.all) == expected)
        #expect(Desktop.fingerprint([Screens.portrait, Screens.laptop, Screens.external]) == expected)
        #expect(Desktop.fingerprint([Screens.laptop]) == "0,0,1512,982")
        var moved = Screens.external
        moved.frame.origin.y = -200
        #expect(Desktop.fingerprint([Screens.laptop, moved, Screens.portrait]) != expected)
    }

    @Test func fingerprintIgnoresVisibleFrameAndName() {
        var dockShown = Screens.laptop
        dockShown.visibleFrame = CGRect(x: 0, y: 70, width: 1512, height: 874)
        dockShown.name = "Color LCD"
        #expect(Desktop.fingerprint([dockShown]) == Desktop.fingerprint([Screens.laptop]))
    }
}
