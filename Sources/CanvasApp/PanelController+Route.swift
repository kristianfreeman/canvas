import AppKit
import CanvasCore

/// Which renderer draws the panel. Content goes native first; when the
/// native render needs WebKit, the panel trades its content for a page and
/// renders the same request there, without moving its window.
extension PanelController {
    /// Renders the request with the renderer its content routes to.
    func render() {
        guard isOpen else { return }
        let wanted = hosts?.route(for: request) ?? renderer
        if case .swap(let target) = RouteStep.step(current: renderer, wanted: wanted) {
            switchRenderer(to: target)
        }
        caller.trace?.route = renderer.rawValue
        dispatchRender()
    }

    /// The native tree needs WebKit, at the first render or after a later
    /// change: remember the content and render it in a page.
    func fallBackToWeb() {
        guard isOpen, renderer == .native, let hosts else { return }
        debugLog("fallback \(id) to WebKit")
        hosts.record(.web, for: request)
        guard hosts.hasWebRenderer else {
            caller.renderFinished(error: "web renderer not found at \(hosts.indexURL.path)",
                                  wait: request.wait, stream: request.stream)
            return
        }
        switchRenderer(to: .web)
        caller.trace?.route = "fallback"
        dispatchRender()
    }

    /// Trades contents with a host of `target`: the one kept from the last
    /// switch, else a pooled one. A shown panel keeps drawing the old
    /// content until the new one has drawn.
    private func switchRenderer(to target: Renderer) {
        guard let hosts else { return }
        let other: PanelHost
        if let standby, standby.renderer == target {
            other = standby
            self.standby = nil
        } else {
            other = hosts.take(target).host
        }
        ChannelHub.shared.remove(content)
        content.delegate = nil
        host.swapContent(with: other, keepShowing: revealed)
        content.delegate = self
        if let previous = standby { hosts.recycle(previous) }
        standby = other
        onRendererChange?()
    }

    /// The content drew after a render. A page still has to paint before
    /// the old content's view can go.
    func drew() {
        guard let waiting = standby else { return }
        guard content.revealsOnPaint, revealed else { return releaseStandby() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak waiting] in
            guard let self, let waiting, self.standby === waiting else { return }
            self.releaseStandby()
        }
    }

    /// The old content's host goes back to its pool.
    func releaseStandby() {
        host.settle()
        guard let standby else { return }
        self.standby = nil
        hosts?.recycle(standby)
    }
}
