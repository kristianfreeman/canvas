import AppKit
import CanvasCore

/// What the content reports, from either renderer.
extension PanelController: PanelContentDelegate {
    func contentDidReload() {
        if renderSeq > 0 { render() }
    }

    func contentDidPaint() {
        caller.trace?.mark(.painted)
        if revealed {
            if standby != nil { releaseStandby() }
            return
        }
        paintSeen = true
        if awaitingPaint { revealSoon() }
    }

    /// Answers a caller still waiting on the render (the page failed to
    /// load); later errors only show in the panel.
    func contentDidReportError(_ message: String) {
        debugLog("content error \(id): \(message)")
        caller.renderFinished(error: message, wait: request.wait, stream: request.stream)
    }

    func contentDidResize(height: CGFloat) {
        guard isOpen, height > 0 else { return }
        layout.contentHeight = height
        if revealed || awaitingPaint { applyFrame() }
    }

    func contentDidSubmit(_ value: Any) {
        guard request.wait else { return }
        close(result: value)
    }

    func contentDidRequestClose() {
        close()
    }

    func contentDidRequestEscapeClose() {
        if panel.escapeCloses { close() }
    }

    func contentNeedsWeb() {
        fallBackToWeb()
    }
}
