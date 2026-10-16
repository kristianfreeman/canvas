import AppKit
import SwiftUI

/// The hosting view a native panel shows. It sizes like any subview of the
/// panel surface (no SwiftUI-driven window sizing) and reports width
/// changes, which change the content's natural height.
final class NativeHostingView: NSHostingView<NativePanelView> {
    var onWidthChange: (() -> Void)?

    required init(rootView: NativePanelView) {
        super.init(rootView: rootView)
        sizingOptions = []
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) is not supported") }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { onWidthChange?() }
    }
}
