import CoreGraphics

/// Panels in one `--stack` group, laid out in slots 12 pt apart.
public enum Stacking {
    public static let gap: CGFloat = 12

    /// Frames for a group's panels, oldest first. `homes` are where each
    /// panel would go on its own (its placement at its current size). The
    /// first keeps its home; each later panel keeps its home x and sits past
    /// the previous one, away from the anchor edge: below it for top and
    /// center anchors, above it for bottom. A slot that would leave the
    /// visible frame stops at its edge, overlapping the slot before, so
    /// every frame stays on screen. Call again with the survivors to reflow
    /// after one closes.
    public static func frames(homes: [CGRect], anchor: Anchor.Vertical, in visible: CGRect) -> [CGRect] {
        var frames: [CGRect] = []
        for home in homes {
            guard let previous = frames.last else {
                frames.append(home.clamped(inside: visible))
                continue
            }
            var slot = home
            slot.origin.y = anchor == .bottom ? previous.maxY + gap : previous.minY - gap - home.height
            frames.append(slot.clamped(inside: visible))
        }
        return frames
    }
}
