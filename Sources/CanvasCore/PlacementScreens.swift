import Foundation

/// One display, in AppKit global coordinates (origin at the bottom-left of
/// the main screen, y up).
public struct ScreenInfo: Equatable, Sendable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var name: String
    /// 1-based position in `NSScreen.screens`, as `--screen N` counts.
    public var index: Int
    /// The screen with the menu bar, `NSScreen.screens.first`.
    public var isMain: Bool

    public init(frame: CGRect, visibleFrame: CGRect, name: String = "", index: Int = 1, isMain: Bool = false) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.name = name
        self.index = index
        self.isMain = isMain
    }
}

/// The screen `selector` names, with the fallbacks of `Desktop.screen(for:)`.
public func selectScreen(
    _ selector: ScreenSelector,
    screens: [ScreenInfo],
    mouse: CGPoint,
    focusedWindowFrame: CGRect? = nil
) -> ScreenInfo? {
    Desktop(screens: screens, mouse: mouse, focusedWindow: focusedWindowFrame).screen(for: selector)
}

/// The displays, the cursor and the frontmost window: everything screen
/// selection and placement read from the system.
public struct Desktop: Sendable {
    public var screens: [ScreenInfo]
    public var mouse: CGPoint
    public var focusedWindow: CGRect?

    public init(screens: [ScreenInfo], mouse: CGPoint, focusedWindow: CGRect? = nil) {
        self.screens = screens
        self.mouse = mouse
        self.focusedWindow = focusedWindow
    }

    /// The screen `selector` names. A selector that matches nothing (an
    /// unplugged display, no focused window) falls back to the mouse's
    /// screen. Nil only when there are no screens.
    public func screen(for selector: ScreenSelector) -> ScreenInfo? {
        let chosen: ScreenInfo?
        switch selector {
        case .mouse: chosen = nil
        case .main: chosen = screens.first(where: \.isMain) ?? screens.first
        case .focused: chosen = focusedWindow.flatMap(screen(containing:))
        case .index(let index): chosen = screens.first { $0.index == index }
        case .name(let name): chosen = screens.first { $0.name.range(of: name, options: .caseInsensitive) != nil }
        }
        return chosen ?? mouseScreen
    }

    /// The screen under the cursor, or the nearest one when the cursor is
    /// off every screen.
    public var mouseScreen: ScreenInfo? {
        screens.min { Self.distance(mouse, $0.frame) < Self.distance(mouse, $1.frame) }
    }

    /// The screen that holds most of `rect`, or nil when it is off-screen.
    public func screen(containing rect: CGRect) -> ScreenInfo? {
        Self.screen(containing: rect, in: screens)
    }

    static func screen(containing rect: CGRect, in screens: [ScreenInfo]) -> ScreenInfo? {
        let overlaps = screens.map { ($0, Self.area($0.frame.intersection(rect))) }
        guard let best = overlaps.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        return best.0
    }

    /// Identifies the display arrangement: the screens' frames, sorted so
    /// the order AppKit lists them in doesn't matter.
    public static func fingerprint(_ screens: [ScreenInfo]) -> String {
        screens.map(\.frame)
            .sorted { ($0.minX, $0.minY, $0.width, $0.height) < ($1.minX, $1.minY, $1.width, $1.height) }
            .map { [$0.minX, $0.minY, $0.width, $0.height].map { String(Int($0.rounded())) }.joined(separator: ",") }
            .joined(separator: ";")
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
