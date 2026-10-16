import AppKit
import CanvasCore

/// The drawing half of a native panel: the `ViewTree` the ops land in, the
/// kit's surface over it in a hosting view, its theme, the error box and
/// its height. Main thread.
final class NativePanelSurface {
    let link = NativeContextTree()
    let hosting: NativeHostingView
    private(set) var surface: NativeSurface
    private var mode = ThemeMode.dark
    private var accent: String?
    private var showsError = false
    private(set) var lastHeight: CGFloat?
    weak var events: NativeEvents? {
        didSet { surface.events = events }
    }

    init(size: NSSize) {
        let surface = NativeSurface(root: link.tree.root)
        self.surface = surface
        hosting = NativeHostingView(rootView: NativePanelView(surface: surface))
        hosting.frame = NSRect(origin: .zero, size: size)
    }

    var tree: ViewTree { link.tree }

    var title: String {
        get { surface.title }
        set { surface.title = newValue }
    }

    func setMode(_ mode: ThemeMode) {
        self.mode = mode
        updateTheme()
    }

    func setAccent(_ accent: String) {
        self.accent = accent
        updateTheme()
    }

    /// A new, empty tree and surface, for a new or replaced context.
    func rebuild(title: String) {
        link.reset()
        showsError = false
        lastHeight = nil
        let surface = NativeSurface(root: link.tree.root, title: title, theme: surface.theme)
        surface.events = events
        self.surface = surface
        hosting.rootView = NativePanelView(surface: surface)
    }

    private func updateTheme() {
        let theme = Theme(mode: mode, accent: accent)
        if theme != surface.theme { surface.theme = theme }
    }

    // MARK: Error box

    func showError(_ message: String) {
        clearError()
        do {
            try link.tree.apply(NativeErrorNodes.ops(message: message))
            showsError = true
        } catch {
            debugLog("native error box failed: \(error)")
        }
    }

    func clearError() {
        guard showsError else { return }
        showsError = false
        try? link.tree.apply(NativeErrorNodes.removal)
    }

    // MARK: Height

    /// The natural height at the hosting view's width, from the panel's own
    /// layout: everything outside the scroll view plus the content's full
    /// height. Holds while the view is at least as tall as header and footer.
    @discardableResult
    func measure() -> CGFloat {
        hosting.layoutSubtreeIfNeeded()
        let laidOut = surface.laidOut
        let height = hosting.bounds.height - laidOut.viewport + laidOut.content
        lastHeight = height
        return height
    }
}
