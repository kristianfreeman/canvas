import AppKit
import CanvasCore

/// Hiding an open panel without closing it, for hotkeys and `toggle --all`.
extension PanelController {
    var stashState: PanelStash.State? {
        guard isOpen, revealed else { return nil }
        return stashed ? .stashed : .shown
    }

    /// Orders the window out. Content, state, channels and any waiting
    /// caller stay as they are.
    func stash() {
        guard isOpen, revealed, !stashed else { return }
        stashed = true
        panel.orderOut(nil)
        debugLog("stash \(id)")
        if let stack { onRestack?(stack) }
    }

    func unstash(focus focused: Bool) {
        guard isOpen, stashed else { return }
        stashed = false
        debugLog("unstash \(id)")
        if let stack { onRestack?(stack) }
        if focused { focus() } else { panel.orderFrontRegardless() }
    }

    func apply(_ action: PanelStash.Action, focus focused: Bool) {
        switch action {
        case .stash: stash()
        case .unstash: unstash(focus: focused)
        }
    }
}
