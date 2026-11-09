import AppKit
import CanvasCore

/// One panel per id: its host (window and content), the file watcher, the
/// CLI caller waiting on it, and any data streams feeding it.
final class PanelController: NSObject, NSWindowDelegate {
    let id: String
    let created = Date()
    let host: PanelHost
    /// Hosts of either renderer, for a fallback or a switch back to native.
    weak var hosts: HostPools?
    /// The host holding the content shown before a renderer switch, until
    /// the new content has drawn.
    var standby: PanelHost?
    var onClose: ((PanelController) -> Void)?
    /// The panel became visible for the first time.
    var onReveal: (() -> Void)?
    /// A stack group needs laying out again: a member moved in or out of it
    /// or changed size.
    var onRestack: ((String) -> Void)?
    /// The panel switched between the native and WebKit renderers.
    var onRendererChange: (() -> Void)?

    var request: ShowRequest
    var layout: PanelLayout
    /// The desktop of the last placement. Until the panel is revealed it is
    /// placed again on it each time the content reports a height.
    var desktop: Desktop
    /// The frame Canvas last gave the window; a move to anywhere else came
    /// from the user.
    var expectedFrame: NSRect?
    var pendingSave: DispatchWorkItem?
    let caller: PanelCaller

    var renderSeq = 0
    var paintSeen = false
    var awaitingPaint = false
    var revealed = false
    var revealFallback: DispatchWorkItem?
    /// The macOS accent last sent to the content, when the request names none.
    var systemAccent: String?
    private(set) var closed = false
    /// Hidden by a hotkey or `toggle --all` while still open.
    var stashed = false
    /// Set at close: the panel can wait hidden for the same request.
    private(set) var mayRest = false

    var streams: [DataStream] = []
    var coalescer = DataCoalescer<Any>()
    private var watcher: FileWatcher?

    var panel: CanvasPanel { host.panel }
    var content: PanelContent { host.content }
    var renderer: Renderer { host.renderer }
    var isOpen: Bool { !closed }

    init(request: ShowRequest, host: PanelHost) {
        self.request = request
        self.host = host
        id = request.id
        layout = PanelLayout(placement: request.placement)
        desktop = .current(for: request.placement.screen)
        caller = PanelCaller(panelID: request.id)
        super.init()
        content.delegate = self
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
    }

    // MARK: Lifecycle

    /// Moves the (parked or new) host into place, still invisible, and
    /// renders. The panel is revealed once the content has drawn.
    func start() {
        layout.remembered = FrameStore.shared.restore(id: id, placement: request.placement, screens: desktop.screens)
        host.park(at: panel.frame, appearance: requestedAppearance)
        panel.applyTraits(of: layout.placement)
        place()
        startWatching()
        render()
    }

    /// A stream request hands the connection to a `DataStream` first.
    func attach(caller client: Client) {
        if request.stream {
            DataStream(client: client, panel: self, answersAtEnd: !request.wait).start()
        }
        caller.attach(client)
    }

    func replace(with new: ShowRequest, caller client: Client) {
        caller.finish(["event": "replaced"])
        let pathChanged = new.path != request.path
        request = new
        panel.appearance = requestedAppearance
        if pathChanged { startWatching() }
        attach(caller: client)
        applyPlacement(new.placement)
        if stashed { unstash(focus: new.focus) } else if revealed, new.focus { focus() }
        render()
    }

    func close() {
        close(result: nil)
    }

    /// Hides first and answers the caller; the hosts are recycled later.
    func close(result: Any?) {
        guard !closed else { return }
        closed = true
        stashed = false
        panel.orderOut(nil)
        debugLog("close \(id)")
        caller.finish(result.map { ["event": "result", "value": $0] } ?? ["event": "closed"])
        let open = streams
        streams.removeAll()
        open.forEach { $0.panelClosed() }
        revealFallback?.cancel()
        revealFallback = nil
        if let save = pendingSave {
            save.perform()
            save.cancel()
        }
        watcher?.stop()
        watcher = nil
        mayRest = revealed && renderer == .native && standby == nil && PanelRest.mayRest(request)
            && !ChannelHub.shared.isSubscribed(content) && !content.hasTimers
        ChannelHub.shared.remove(content)
        content.delegate = nil
        panel.delegate = nil
        panel.onCancel = nil
        onClose?(self)
    }

    /// Shows a resting panel again for a request that draws the same thing,
    /// without rendering, and answers the caller at once.
    func reopen(_ new: ShowRequest, caller client: Client) {
        closed = false
        mayRest = false
        request = new
        content.delegate = self
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        desktop = .current(for: new.placement.screen)
        _ = layout.apply(new.placement)
        layout.remembered = FrameStore.shared.restore(id: id, placement: new.placement, screens: desktop.screens)
        startWatching()
        caller.attach(client)
        refreshAppearance()
        place()
        caller.renderFinished(error: nil, wait: false, stream: false)
        caller.trace?.mark(.visible)
        if new.focus { focus() } else { panel.orderFrontRegardless() }
    }

    var listing: [String: Any] {
        var entry: [String: Any] = [
            "id": id,
            "title": request.title ?? NSNull(),
            "kind": request.kind,
            "renderer": renderer.rawValue,
            "path": request.path ?? NSNull(),
            "wait": request.wait && caller.isAttached,
            "hidden": stashed,
            "frame": panel.frame.wire,
            "screen": panel.screen?.localizedName ?? layout.screen?.name ?? NSNull()
        ]
        entry.merge(layout.placement.listing) { $1 }
        return entry
    }

    private var requestedAppearance: NSAppearance? {
        switch request.theme {
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        case .auto, nil: return nil
        }
    }

    /// What `theme` resolves to: the request's, else the panel's appearance.
    var themeMode: ThemeMode {
        switch request.theme {
        case .dark: return .dark
        case .light: return .light
        case .auto, nil:
            return panel.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        }
    }

    // MARK: Live reload

    private func startWatching() {
        watcher?.stop()
        watcher = nil
        guard let path = request.path else { return }
        watcher = FileWatcher(path: path) { [weak self] in self?.fileChanged() }
    }

    func fileChanged() {
        guard !closed, let path = request.path,
              let text = try? String(contentsOfFile: path, encoding: .utf8),
              text != request.source else { return }
        debugLog("reload \(id) from \(path)")
        request.source = text
        render()
    }

    // MARK: Window

    func windowDidMove(_: Notification) {
        guard revealed, !panel.inLiveResize, panel.frame != expectedFrame else { return }
        userMoved(.drag)
    }

    func windowDidEndLiveResize(_: Notification) {
        userMoved(.resize)
        panel.invalidateShadow()
    }
}
