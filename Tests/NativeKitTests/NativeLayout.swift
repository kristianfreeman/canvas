import AppKit
@testable import CanvasApp
import CanvasCore
import SwiftUI

/// Sizes native panels offscreen, without a panel: the height of the header,
/// the full content and the footer at a given width.
enum NativeLayout {
    /// One-off: builds a hosting controller for this call. A panel that
    /// resizes often should keep a `NativeMeasurer`.
    @MainActor
    static func fittingHeight(root: ViewNode, width: CGFloat, theme: Theme) -> CGFloat {
        NativeMeasurer(surface: NativeSurface(root: root, theme: theme)).height(width: width)
    }

    @MainActor
    static func fittingHeight(surface: NativeSurface, width: CGFloat) -> CGFloat {
        NativeMeasurer(surface: surface).height(width: width)
    }
}

/// Keeps an offscreen hosting controller of a surface's unscrolled panel,
/// so repeated measurements only lay out what changed.
@MainActor
final class NativeMeasurer {
    private let host: NSHostingController<NativePanelView>

    init(surface: NativeSurface) {
        host = NSHostingController(rootView: NativePanelView(surface: surface, scrolls: false))
        host.sizingOptions = []
    }

    /// Tree changes since the last call are laid out first, at `width`, so
    /// the height is current. Laid out at a zero-width frame, every text
    /// would wrap at each word first.
    func height(width: CGFloat) -> CGFloat {
        host.view.setFrameSize(NSSize(width: width, height: host.view.frame.height))
        host.view.layoutSubtreeIfNeeded()
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }
}
