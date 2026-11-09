import Foundation

/// A stashed panel is hidden by a hotkey or `toggle --all` without closing:
/// its content, state, channels and caller stay as they are, and it comes
/// back as it was. These rules say what a toggle does.
public enum PanelStash {
    public enum State: Equatable {
        case shown, stashed
    }

    public enum Action: Equatable {
        case stash, unstash
    }

    /// `toggle --all` and the global hotkey: stash every shown panel, or,
    /// when none is shown, bring back every stashed one.
    public static func toggleAll<ID>(_ panels: [(id: ID, state: State)]) -> (action: Action, ids: [ID]) {
        let shown = panels.filter { $0.state == .shown }.map(\.id)
        if !shown.isEmpty { return (.stash, shown) }
        return (.unstash, panels.filter { $0.state == .stashed }.map(\.id))
    }

    /// What a panel hotkey does to its id. Nil state means no panel is open
    /// under the id, so the binding's request shows it again.
    public static func toggle(_ state: State?) -> Action? {
        switch state {
        case .shown: .stash
        case .stashed: .unstash
        case nil: nil
        }
    }
}
