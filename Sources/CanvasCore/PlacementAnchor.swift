import CoreGraphics

/// The edges that stay put when a panel changes size. The vertical part is
/// the growth anchor: a top-anchored panel grows downward, a bottom-anchored
/// one upward, a centered one both ways.
public struct Anchor: Equatable, Hashable, Codable, Sendable {
    public enum Vertical: String, Codable, Sendable {
        case top, center, bottom
    }

    public enum Horizontal: String, Codable, Sendable {
        case left, center, right
    }

    public var vertical: Vertical
    public var horizontal: Horizontal

    public init(_ vertical: Vertical, _ horizontal: Horizontal) {
        self.vertical = vertical
        self.horizontal = horizontal
    }

    /// The anchor of a frame the user dragged: the visible frame's nearer
    /// edge on each axis. Ties go to the top and the left.
    public static func nearest(to frame: CGRect, in visible: CGRect) -> Self {
        Self(frame.midY >= visible.midY ? .top : .bottom, frame.midX > visible.midX ? .right : .left)
    }

    /// The anchored point of `frame`: its anchored edge, or its center line,
    /// on each axis.
    public func point(of frame: CGRect) -> CGPoint {
        CGPoint(x: Self.value(horizontal.side, frame.minX, frame.maxX),
                y: Self.value(vertical.side, frame.minY, frame.maxY))
    }

    /// A frame of `size` whose anchored point is `point`, inside `visible`.
    public func frame(at point: CGPoint, size: CGSize, in visible: CGRect) -> CGRect {
        let x = Self.start(horizontal.side, point.x, size.width)
        let y = Self.start(vertical.side, point.y, size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height).clamped(inside: visible)
    }

    /// `frame` resized to `size` with its anchored point kept.
    public func resized(_ frame: CGRect, to size: CGSize, in visible: CGRect) -> CGRect {
        self.frame(at: point(of: frame), size: size, in: visible)
    }

    private static func value(_ side: Side, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        switch side {
        case .low: low
        case .middle: (low + high) / 2
        case .high: high
        }
    }

    private static func start(_ side: Side, _ point: CGFloat, _ extent: CGFloat) -> CGFloat {
        switch side {
        case .low: point
        case .middle: (point - extent / 2).rounded(.down)
        case .high: point - extent
        }
    }
}

/// An axis position in AppKit terms: `low` is the left or bottom edge.
enum Side {
    case low, middle, high
}

extension Anchor.Vertical {
    var side: Side {
        switch self {
        case .top: .high
        case .center: .middle
        case .bottom: .low
        }
    }
}

extension Anchor.Horizontal {
    var side: Side {
        switch self {
        case .left: .low
        case .center: .middle
        case .right: .high
        }
    }
}

extension CGRect {
    /// Shrunk to fit `visible` and moved fully inside it, origin on whole
    /// points.
    func clamped(inside visible: CGRect) -> CGRect {
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        let x = min(max(origin.x.rounded(.down), visible.minX), visible.maxX - width)
        let y = min(max(origin.y.rounded(.down), visible.minY), visible.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
