import Foundation

extension Placement {
    /// The window fields of a `list` entry, as the window actually behaves.
    public var listing: [String: Any] {
        [
            "level": effectiveLevel.rawValue,
            "pinned": pin,
            "clickThrough": clickThrough,
            "stack": stack ?? NSNull()
        ]
    }
}

extension CGRect {
    /// `{x, y, width, height}` in whole points, as `list` and `moved` report
    /// frames.
    public var wire: [String: Int] {
        [
            "x": Int(minX.rounded()), "y": Int(minY.rounded()),
            "width": Int(width.rounded()), "height": Int(height.rounded())
        ]
    }
}
