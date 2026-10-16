import CoreGraphics

/// One panel's layout: its placement, the page's height, a width the user
/// dragged to, and the anchor that keeps an edge put while the height
/// changes. Frames are in AppKit global coordinates.
public struct PanelLayout {
    public static let defaultWidth: CGFloat = 720
    public static let minWidth = Placement.minWidth
    public static let minHeight: CGFloat = 80
    public static let fallbackHeight = Placement.fallbackHeight
    public static let maxHeightFraction: CGFloat = 0.85

    public private(set) var placement: Placement
    public var contentHeight: CGFloat?
    /// A width the user dragged to (or a restored one). It wins until a
    /// request gives `width`.
    public var userWidth: CGFloat?
    /// Set from `FrameStore.restore` before the first `place(in:)`.
    public var remembered: RememberedFrame?
    public private(set) var anchor: Anchor
    /// The screen of the last `place(in:)`.
    public private(set) var screen: ScreenInfo?
    private var anchorPoint: CGPoint?
    private var lastFrame: CGRect?

    public init(placement: Placement) {
        self.placement = placement
        anchor = placement.presetAnchor ?? Anchor(.top, .left)
    }

    /// Whether the panel knows its height yet.
    public var hasHeight: Bool { contentHeight != nil || placement.height != nil }

    public func size(in visible: CGRect) -> CGSize {
        CGSize(width: placement.width(in: visible, override: userWidth),
               height: placement.height(contentHeight: contentHeight, in: visible))
    }

    /// Where the panel goes on its own at its current size, ignoring any
    /// remembered frame. Stacks start from these.
    public func homeFrame(on screen: ScreenInfo, mouse: CGPoint) -> CGRect {
        placement.frame(size: size(in: screen.visibleFrame), in: screen.visibleFrame, mouse: mouse)
    }

    /// Places the panel: at its remembered frame when there is one on a
    /// connected screen (and `screen`, if given, selects that screen), else
    /// by its placement on the selected screen. Sets `anchor` and `screen`.
    /// Nil only when there are no screens.
    public mutating func place(in desktop: Desktop) -> CGRect? {
        if let restored = restore(in: desktop) { return restored }
        guard let screen = desktop.screen(for: placement.screen) else { return nil }
        let frame = homeFrame(on: screen, mouse: desktop.mouse)
        commit(frame, anchor: placement.anchor(for: frame, mouse: desktop.mouse), on: screen)
        return frame
    }

    /// The remembered frame at the current size. Its anchored point is the
    /// remembered one, so a frame squeezed against an edge returns there.
    private mutating func restore(in desktop: Desktop) -> CGRect? {
        guard let remembered, let screen = desktop.screen(containing: remembered.frame) else { return nil }
        if placement.given.contains(.screen), desktop.screen(for: placement.screen) != screen { return nil }
        if !placement.given.contains(.width) { userWidth = remembered.width }
        let frame = remembered.frame(size: size(in: screen.visibleFrame), in: screen.visibleFrame)
        commit(frame, anchor: remembered.anchor, on: screen)
        anchorPoint = remembered.anchor.point(of: remembered.frame)
        return frame
    }

    private mutating func commit(_ frame: CGRect, anchor: Anchor, on screen: ScreenInfo) {
        self.anchor = anchor
        self.screen = screen
        anchorPoint = anchor.point(of: frame)
        lastFrame = frame
    }

    /// The frame at the current size, keeping the anchored point. When
    /// `current` isn't the frame this layout last returned (a drag, a stack
    /// reflow, AppKit moving the window), the anchor is re-taken from it.
    public mutating func resize(_ current: CGRect, in visible: CGRect) -> CGRect {
        resize(current, to: size(in: visible), in: visible)
    }

    private mutating func resize(_ current: CGRect, to size: CGSize, in visible: CGRect) -> CGRect {
        let point = current == lastFrame ? anchorPoint ?? anchor.point(of: current) : anchor.point(of: current)
        let frame = anchor.frame(at: point, size: size, in: visible)
        anchorPoint = point
        lastFrame = frame
        return frame
    }

    public enum UserMove { case drag, resize }

    /// After the user drags or resizes the panel: keep their width and
    /// anchor to the nearer edges, as a remembered frame would. A drag takes
    /// the panel out of its stack, so the stack stops putting it back.
    /// Returns the stack group it left.
    @discardableResult
    public mutating func userMoved(_ move: UserMove, to frame: CGRect, in visible: CGRect) -> String? {
        userWidth = frame.width
        anchor = .nearest(to: frame, in: visible)
        anchorPoint = anchor.point(of: frame)
        lastFrame = frame
        guard move == .drag, let group = placement.stack else { return nil }
        placement.stack = nil
        placement.given.remove(.stack)
        return group
    }

    /// Merges a later request's placement (a replacing `show`, or `move`)
    /// and says what the open panel should do: `.place` calls for
    /// `place(in:)`, `.resize` for `resize(_:in:)`.
    public mutating func apply(_ newer: Placement) -> Placement.Change {
        placement = placement.merging(newer)
        if newer.given.contains(.width) { userWidth = nil }
        let change = Placement.change(for: newer)
        if change == .place { remembered = nil }
        return change
    }

    /// Frames for a stack group's layouts, oldest first, on the first
    /// one's screen.
    public static func stackedFrames(_ layouts: [Self], on screen: ScreenInfo, mouse: CGPoint) -> [CGRect] {
        let homes = layouts.map { $0.homeFrame(on: screen, mouse: mouse) }
        return Stacking.frames(homes: homes, anchor: layouts.first?.anchor.vertical ?? .top, in: screen.visibleFrame)
    }
}
