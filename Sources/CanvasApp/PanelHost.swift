import AppKit
import CanvasCore

/// A panel window and its content. Hosts outlive panel ids: a pool parks
/// one, a new panel takes it, and a closed panel's host goes back. Two
/// hosts can trade contents, which is how an open panel changes renderer
/// without moving its window.
final class PanelHost {
    let panel: CanvasPanel
    private let surface: SurfaceView
    private(set) var content: PanelContent
    /// A previous content's view, still on show above the new one until it
    /// has drawn, and the host that now owns it.
    private var held: (view: NSView, owner: PanelHost)?

    var renderer: Renderer { content.renderer }

    init(content: PanelContent, frame: NSRect) {
        self.content = content
        panel = CanvasPanel(frame: frame)
        surface = SurfaceView(size: frame.size)
        panel.contentView = surface
        surface.show(content.view)
        panel.escapeEndsEditingFirst = content.renderer == .native
    }

    static func web(indexURL: URL) -> PanelHost {
        let page = WebPage(indexURL: indexURL)
        let host = PanelHost(content: page, frame: parkingFrame)
        page.load()
        return host
    }

    static func native(contexts: @escaping () -> NativeContext) -> PanelHost {
        PanelHost(content: NativePanelContent(contexts: contexts), frame: parkingFrame)
    }

    /// Ordered in but invisible and inert. WebKit keeps an on-screen page
    /// live, so layout and animation frames keep running while it waits.
    func park(at frame: NSRect, appearance: NSAppearance? = nil) {
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = CanvasPanel.parkedBehavior
        panel.applyTraits(of: Placement())
        panel.appearance = appearance
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
    }

    /// Visible, and interactive unless `placement` is click-through. The
    /// caller orders it front.
    func unpark(_ placement: Placement) {
        panel.applyPresence(of: placement)
    }

    /// Trades contents with `other`. With `keepShowing`, this panel keeps
    /// drawing its old content above the new one until `settle()`.
    func swapContent(with other: PanelHost, keepShowing: Bool) {
        let mine = content
        content = other.content
        other.content = mine
        panel.escapeEndsEditingFirst = content.renderer == .native
        other.panel.escapeEndsEditingFirst = mine.renderer == .native
        if let held, held.view === content.view {
            self.held = nil
            other.surface.show(mine.view)
            return
        }
        settle()
        surface.show(content.view, under: keepShowing ? mine.view : nil)
        if keepShowing {
            held = (mine.view, other)
        } else {
            other.surface.show(mine.view)
        }
    }

    /// The new content has drawn: the old one's view goes to its new host.
    func settle() {
        guard let held else { return }
        self.held = nil
        held.owner.surface.show(held.view)
    }

    func tearDown() {
        settle()
        panel.orderOut(nil)
        content.tearDown()
        panel.delegate = nil
        panel.onCancel = nil
        panel.contentView = nil
        panel.close()
    }

    /// Where a parked panel waits: the default size, centered on the main
    /// screen, so a typical show doesn't change its width.
    static var parkingFrame: NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(PanelLayout.defaultWidth, visible.width), height: PanelLayout.fallbackHeight)
        return NSRect(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height)
    }
}
