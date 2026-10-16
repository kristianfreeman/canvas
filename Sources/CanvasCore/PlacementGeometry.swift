import CoreGraphics

/// Frames for a placement on one screen. Every frame is in AppKit global
/// coordinates and lies fully inside the visible frame it was computed for.
extension Placement {
    public static let minWidth: CGFloat = 240
    public static let fallbackHeight: CGFloat = 200
    public static let mouseOffset: CGFloat = 12

    /// `override` (a width the user dragged to) or `width`, at least 240 and
    /// at most the visible width.
    public func width(in visible: CGRect, override: CGFloat? = nil) -> CGFloat {
        min(max(override ?? width.resolved(in: visible.width), Self.minWidth), visible.width)
    }

    /// A fixed `height`, or the content's height (200 until the page
    /// reports) bounded by `maxHeight`. `minHeight` floors both; the result
    /// never exceeds the visible height.
    public func height(contentHeight: CGFloat?, in visible: CGRect) -> CGFloat {
        let floor = Self.points(minHeight, of: visible.height)
        if let height {
            return min(max(Self.points(height, of: visible.height), floor), visible.height)
        }
        let cap = min(Self.points(maxHeight, of: visible.height), visible.height)
        let natural = (contentHeight ?? Self.fallbackHeight).rounded(.up)
        return min(max(natural, min(floor, cap)), cap)
    }

    /// A size in points: percentages round down, but never to nothing.
    private static func points(_ length: Length, of extent: CGFloat) -> CGFloat {
        max(length.resolved(in: extent), 1)
    }

    public func size(contentHeight: CGFloat?, in visible: CGRect) -> CGSize {
        CGSize(width: width(in: visible), height: height(contentHeight: contentHeight, in: visible))
    }

    /// The panel's frame on `screen` for a page of `contentHeight` (nil
    /// before the page reports).
    public func placedFrame(contentHeight: CGFloat?, on screen: ScreenInfo, mouse: CGPoint) -> CGRect {
        let visible = screen.visibleFrame
        return frame(size: size(contentHeight: contentHeight, in: visible), in: visible, mouse: mouse)
    }

    /// A frame of `size` placed on `visible` by `at`, the preset or the
    /// cursor.
    public func frame(size: CGSize, in visible: CGRect, mouse: CGPoint) -> CGRect {
        guard let anchor = presetAnchor else { return Self.mouseFrame(size, in: visible, mouse: mouse) }
        return anchor.frame(at: anchorPoint(in: visible), size: size, in: visible)
    }

    /// The growth anchor for a panel placed at `frame`. A `mouse` panel
    /// keeps the edge nearest the cursor on each axis.
    public func anchor(for frame: CGRect, mouse: CGPoint) -> Anchor {
        presetAnchor ?? Anchor(
            abs(frame.maxY - mouse.y) <= abs(frame.minY - mouse.y) ? .top : .bottom,
            abs(frame.minX - mouse.x) <= abs(frame.maxX - mouse.x) ? .left : .right)
    }

    /// The vertical margin: `top` keeps 64 pt unless a margin is given.
    var verticalMargin: CGFloat {
        margin ?? (position == .top && at == nil ? Self.topMargin : Self.defaultMargin)
    }

    /// Where the anchored point of an `at` or preset placement sits.
    func anchorPoint(in visible: CGRect) -> CGPoint {
        if let at {
            let dx = at.x.resolved(in: visible.width)
            let dy = at.y.resolved(in: visible.height)
            return CGPoint(x: at.x.isNegative ? visible.maxX - dx : visible.minX + dx,
                           y: at.y.isNegative ? visible.minY + dy : visible.maxY - dy)
        }
        let anchor = position.anchor ?? Anchor(.center, .center)
        return CGPoint(x: Self.inset(anchor.horizontal.side, visible.minX...visible.maxX, margin ?? Self.defaultMargin),
                       y: Self.inset(anchor.vertical.side, visible.minY...visible.maxY, verticalMargin))
    }

    private static func inset(_ side: Side, _ span: ClosedRange<CGFloat>, _ margin: CGFloat) -> CGFloat {
        switch side {
        case .low: span.lowerBound + margin
        case .middle: (span.lowerBound + span.upperBound) / 2
        case .high: span.upperBound - margin
        }
    }

    /// Below and right of the cursor, flipped left or above when that side
    /// runs off the visible frame.
    static func mouseFrame(_ size: CGSize, in visible: CGRect, mouse: CGPoint) -> CGRect {
        var x = mouse.x + mouseOffset
        if x + size.width > visible.maxX { x = mouse.x - mouseOffset - size.width }
        var y = mouse.y - mouseOffset - size.height
        if y < visible.minY { y = mouse.y + mouseOffset }
        return CGRect(origin: CGPoint(x: x, y: y), size: size).clamped(inside: visible)
    }
}
