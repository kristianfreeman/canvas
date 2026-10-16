import AppKit
import CanvasCore

extension FrameStore {
    static let shared = FrameStore(url: URL(fileURLWithPath: Paths.frames))
}

/// Where the panel goes: placement, content-driven resizing, stacks, later
/// placement changes and the user's drags.
extension PanelController {
    private static let saveDelay = 0.3

    var stack: String? { layout.placement.stack }

    /// Places the panel from scratch on `desktop`. A stacked panel then takes
    /// its slot in the group.
    func place() {
        guard let frame = layout.place(in: desktop) else { return }
        if let stack, let onRestack {
            onRestack(stack)
        } else {
            setFrame(frame)
        }
    }

    /// Follows the page's height: an unrevealed panel is placed again, a
    /// revealed one resized around its growth anchor.
    func applyFrame() {
        guard !panel.inLiveResize else { return }
        guard revealed else { return place() }
        if let stack, let onRestack { return onRestack(stack) }
        guard let visible = panel.screen?.visibleFrame ?? layout.screen?.visibleFrame else { return }
        setFrame(layout.resize(panel.frame, in: visible))
    }

    /// Merges a later placement (a replacing `show`, or `move`) and moves,
    /// resizes or restyles the panel as it asks.
    func applyPlacement(_ newer: Placement) {
        let oldStack = stack
        if newer.forget { FrameStore.shared.forget(id: id) }
        let change = layout.apply(newer)
        panel.applyTraits(of: layout.placement)
        if revealed { panel.applyPresence(of: layout.placement) }
        switch change {
        case .place:
            desktop = .current(for: layout.placement.screen)
            place()
        case .resize: applyFrame()
        case .none: break
        }
        if let oldStack, oldStack != stack { onRestack?(oldStack) }
    }

    /// Sets the window's frame, remembering it as Canvas's own move.
    func setFrame(_ frame: NSRect) {
        expectedFrame = frame
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: revealed, animate: false)
        if revealed { panel.invalidateShadow() }
    }

    /// The user dragged or resized the panel: keep their width and nearer
    /// edges, and save the frame once the drag settles. A dragged panel
    /// leaves its stack, and the rest of the stack closes the gap.
    func userMoved(_ move: PanelLayout.UserMove) {
        let frame = panel.frame
        expectedFrame = frame
        if let visible = panel.screen?.visibleFrame, let left = layout.userMoved(move, to: frame, in: visible) {
            onRestack?(left)
        }
        pendingSave?.cancel()
        let save = DispatchWorkItem { [weak self, id] in
            self?.pendingSave = nil
            FrameStore.shared.remember(id: id, frame: frame, screens: Desktop.current().screens)
        }
        pendingSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: save)
    }
}
