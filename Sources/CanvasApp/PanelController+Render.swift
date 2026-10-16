import AppKit
import CanvasCore

/// Rendering, sizing and the first reveal.
extension PanelController {
    /// The request's payload, with the macOS accent color unless it names one.
    private func makePayload() -> [String: Any] {
        var payload = request.payload
        if request.accent == nil {
            let accent = Accent.hex(in: panel.effectiveAppearance)
            systemAccent = accent
            payload["accent"] = accent
        }
        return payload
    }

    /// Light/dark and the system accent, which can change in System
    /// Settings. Setting them keeps component state, which a render would not.
    func refreshAppearance() {
        guard isOpen, renderSeq > 0 else { return }
        content.setMode(themeMode)
        guard request.accent == nil else { return }
        let accent = Accent.hex(in: panel.effectiveAppearance)
        guard accent != systemAccent else { return }
        systemAccent = accent
        content.setAccent(accent)
    }

    /// One round trip: the content renders and returns its height.
    func dispatchRender() {
        guard isOpen else { return }
        renderSeq += 1
        let seq = renderSeq
        paintSeen = false
        let trace = caller.trace
        trace?.mark(.dispatch)
        content.setMode(themeMode)
        content.render(makePayload()) { [weak self] result in
            if let trace { Self.record(result, in: trace) }
            self?.renderReturned(result, seq: seq)
        }
    }

    private static func record(_ result: RenderResult, in trace: TraceRecord) {
        if let start = result.jsStart { trace.mark(.jsStart, at: start) }
        if let end = result.jsEnd { trace.mark(.jsEnd, at: end) }
    }

    /// Answers the caller right away. A native panel shows now; a web one
    /// once it has painted.
    private func renderReturned(_ result: RenderResult, seq: Int) {
        guard seq == renderSeq, isOpen else { return }
        if result.needsWeb { return fallBackToWeb() }
        if renderer == .native { hosts?.record(.native, for: request) }
        if let error = result.error { debugLog("error \(id): \(error)") }
        caller.renderFinished(error: result.error, wait: request.wait, stream: request.stream)
        if let height = result.height, height > 0 { layout.contentHeight = height }
        drew()
        if revealed {
            applyFrame()
        } else {
            prepareReveal()
        }
    }

    /// Sizes the still invisible panel. A web panel then waits for the
    /// page's `painted` (or a short fallback) so it never shows an
    /// unpainted frame; a native one has drawn already.
    private func prepareReveal() {
        applyFrame()
        if !content.revealsOnPaint {
            reveal()
            return
        }
        if paintSeen {
            revealSoon()
            return
        }
        awaitingPaint = true
        guard revealFallback == nil else { return }
        let item = DispatchWorkItem { [weak self] in self?.reveal() }
        revealFallback = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    /// A turn later, so the layer commit that follows `painted` lands first.
    func revealSoon() {
        DispatchQueue.main.async { [weak self] in self?.reveal() }
    }

    private func reveal() {
        guard !revealed, isOpen else { return }
        revealed = true
        awaitingPaint = false
        revealFallback?.cancel()
        revealFallback = nil
        expectedFrame = panel.frame
        content.prepareToShow()
        host.unpark(layout.placement)
        caller.trace?.mark(.visible)
        if request.focus {
            focus()
        } else {
            panel.orderFrontRegardless()
        }
        panel.invalidateShadow()
        debugLog("reveal \(id) \(renderer.rawValue) frame=\(NSStringFromRect(panel.frame))")
        onReveal?()
    }

    func focus() {
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(content.view)
    }
}
