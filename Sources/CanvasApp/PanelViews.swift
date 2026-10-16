import AppKit
import WebKit
import CanvasCore

final class CanvasPanel: NSPanel {
    var onCancel: (() -> Void)?
    private(set) var escapeCloses = true
    /// Esc handling for native content, which has no page script to do it:
    /// the first Esc only ends editing a field, as on the web.
    var escapeEndsEditingFirst = false

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false)
        level = .floating
        collectionBehavior = Self.shownBehavior
        isExcludedFromWindowsMenu = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: PanelLayout.minWidth, height: PanelLayout.minHeight)
    }

    static let shownBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    static let currentSpaceBehavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary]
    /// A parked panel stays out of Mission Control and window cycling.
    static let parkedBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle
    ]

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Level, resizing and Esc, which apply whether or not the panel is
    /// parked.
    func applyTraits(of placement: Placement) {
        level = placement.effectiveLevel.windowLevel
        if placement.resizable {
            styleMask.insert(.resizable)
        } else {
            styleMask.remove(.resizable)
        }
        escapeCloses = placement.closesOnEscape
    }

    /// Spaces, click-through and opacity, which a parked panel overrides.
    func applyPresence(of placement: Placement) {
        collectionBehavior = placement.effectiveSpaces == .all ? Self.shownBehavior : Self.currentSpaceBehavior
        ignoresMouseEvents = placement.clickThrough
        alphaValue = placement.opacity
    }

    override func cancelOperation(_: Any?) {
        if escapeCloses { onCancel?() }
    }

    override func sendEvent(_ event: NSEvent) {
        guard escapeEndsEditingFirst, event.type == .keyDown, event.keyCode == Self.escapeKeyCode else {
            return super.sendEvent(event)
        }
        if firstResponder is NSText {
            makeFirstResponder(nil)
        } else {
            cancelOperation(nil)
        }
    }

    private static let escapeKeyCode: UInt16 = 53
}

/// Paints the panel surface so nothing flashes before the page does. The
/// colors match the page's `--bg` and `--border`.
final class SurfaceView: NSView {
    private static let darkBackground = NSColor(srgbRed: 0x0a / 255, green: 0x0a / 255, blue: 0x0a / 255, alpha: 1)
    private static let darkBorder = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)
    private static let lightBorder = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.08)

    static let headerHeight: CGFloat = 40
    static let closeButtonWidth: CGFloat = 44

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
    }

    /// A surface with a drag strip over the header, short of the close
    /// button. Content views go under the strip.
    convenience init(size: NSSize) {
        self.init(frame: NSRect(origin: .zero, size: size))
        autoresizingMask = [.width, .height]
        let strip = DragStrip(frame: NSRect(
            x: 0,
            y: bounds.height - Self.headerHeight,
            width: max(0, bounds.width - Self.closeButtonWidth),
            height: Self.headerHeight))
        strip.autoresizingMask = [.width, .minYMargin]
        addSubview(strip)
    }

    /// Adds `view` filling the surface: under `top` when given, so `top`
    /// stays on show until it leaves, else as the topmost content.
    func show(_ view: NSView, under top: NSView? = nil) {
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        let strip = subviews.first { $0 is DragStrip }
        addSubview(view, positioned: .below, relativeTo: top?.superview === self ? top : strip)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? Self.darkBackground : NSColor.white).cgColor
        layer?.borderColor = (dark ? Self.darkBorder : Self.lightBorder).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Transparent strip over the page header that drags the window.
final class DragStrip: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
