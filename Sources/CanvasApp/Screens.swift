import AppKit
import CanvasCore

extension Desktop {
    /// The displays and the cursor now. The frontmost window is read only
    /// when `selector` asks for it, since listing windows isn't free.
    static func current(for selector: ScreenSelector = .mouse) -> Desktop {
        let screens = NSScreen.screens
        let infos = screens.enumerated().map { index, screen in
            ScreenInfo(frame: screen.frame, visibleFrame: screen.visibleFrame, name: screen.localizedName,
                       index: index + 1, isMain: index == 0)
        }
        let focused = selector == .focused ? focusedWindow(mainScreenHeight: screens.first?.frame.height ?? 0) : nil
        return Desktop(screens: infos, mouse: NSEvent.mouseLocation, focusedWindow: focused)
    }

    private static func focusedWindow(mainScreenHeight: CGFloat) -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        return FocusedWindow.frame(of: app.processIdentifier, in: windows, mainScreenHeight: mainScreenHeight)
    }
}

extension Placement.Level {
    /// `top` sits above full-screen apps and the menu bar.
    var windowLevel: NSWindow.Level {
        switch self {
        case .normal: .normal
        case .floating: .floating
        case .top: .statusBar
        }
    }
}
