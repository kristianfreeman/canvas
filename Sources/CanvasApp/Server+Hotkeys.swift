import AppKit
import CanvasCore

/// The global hotkey, panel hotkeys and `toggle --all`.
extension Server {
    var hotkeyCenter: HotkeyCenter { .shared }

    /// At launch: the saved panel hotkeys, then `hotkey` from config.toml,
    /// which wins over a panel hotkey on the same keys. One that macOS
    /// refuses is logged and skipped.
    func registerHotkeys(global: Hotkey?) {
        bindings = HotkeyBindings.load()
        for binding in bindings.sorted {
            do {
                try register(binding)
            } catch {
                Self.report(error)
            }
        }
        setGlobalHotkey(global)
    }

    /// config.toml changed: applies its `hotkey`. Other keys take effect at
    /// the next start.
    func reloadConfig(_ text: String?) {
        let config = text.map(Config.init(parsing:)) ?? Config()
        debugLog("config changed; global hotkey \(config.hotkey?.description ?? "none")")
        setGlobalHotkey(config.hotkey)
    }

    /// Moves the global hotkey, handing keys back to a panel hotkey the old
    /// global one covered.
    func setGlobalHotkey(_ hotkey: Hotkey?) {
        let swap = GlobalHotkeySwap(from: globalHotkey, to: hotkey, bindings: bindings)
        swap.unregister.forEach(hotkeyCenter.unregister)
        if !swap.unregister.isEmpty { globalHotkey = nil }
        for step in swap.register {
            do {
                try register(step)
            } catch {
                Self.report(error)
            }
        }
    }

    private func register(_ step: HotkeyRegistration) throws(HotkeyError) {
        switch step {
        case .global(let hotkey):
            try hotkeyCenter.register(hotkey) { [weak self] in self?.toggleAll(nil) }
            globalHotkey = hotkey
        case .panel(let id, _):
            if let binding = bindings.byID[id] { try register(binding) }
        }
    }

    private static func report(_ error: HotkeyError) {
        FileHandle.standardError.write(Data("canvas-server: \(error.description)\n".utf8))
    }

    private func register(_ binding: HotkeyBinding) throws(HotkeyError) {
        let id = binding.id
        try hotkeyCenter.register(binding.hotkey) { [weak self] in self?.hotkeyPressed(id) }
    }

    /// A show request's `hotkey`, applied before it renders. Returns the
    /// error to answer with, if any.
    func applyHotkey(_ change: HotkeyChange?, json: [String: Any], id: String) -> String? {
        switch change {
        case nil:
            return nil
        case .unbind:
            if let old = bindings.unbind(id) { release(old.hotkey) }
        case .bind(let hotkey):
            if let message = bind(HotkeyBinding(id: id, hotkey: hotkey, request: json)) { return message }
        }
        bindings.save()
        return nil
    }

    private func bind(_ binding: HotkeyBinding) -> String? {
        guard binding.hotkey != globalHotkey else {
            return "hotkey \(binding.hotkey) is the global hotkey in config.toml"
        }
        do {
            try register(binding)
        } catch {
            return error.description
        }
        for old in bindings.bind(binding) where old.hotkey != binding.hotkey { release(old.hotkey) }
        return nil
    }

    /// Unregisters a panel's old hotkey, unless the global hotkey has those
    /// keys: then the panel never held them.
    private func release(_ hotkey: Hotkey) {
        guard hotkey != globalHotkey else { return }
        hotkeyCenter.unregister(hotkey)
    }

    /// A panel hotkey: stash or bring back the open panel, or show it again
    /// from the binding's request.
    func hotkeyPressed(_ id: String) {
        let panel = panels[id]
        if let action = PanelStash.toggle(panel?.stashState) {
            debugLog("hotkey \(id): \(action)")
            panel?.apply(action, focus: true)
            return
        }
        guard panel?.isOpen != true, let binding = bindings.byID[id] else { return }
        debugLog("hotkey \(id): show")
        show(binding.showRequest(), command: .show, .detached())
    }

    /// The global hotkey and `toggle --all`: stash every shown panel, or
    /// bring back the stashed ones. Answers `hidden` or `shown`.
    func toggleAll(_ client: Client?) {
        let open = panels.values.sorted { $0.created < $1.created }
        let states = open.compactMap { panel in panel.stashState.map { (id: panel.id, state: $0) } }
        let (action, ids) = PanelStash.toggleAll(states)
        ids.forEach { panels[$0]?.apply(action, focus: false) }
        debugLog("toggle all: \(action) \(ids)")
        client?.reply(["event": action == .unstash && !ids.isEmpty ? "shown" : "hidden"])
    }

    /// One line per hotkey: the global one, then panel hotkeys by id.
    func listHotkeys(_ client: Client) {
        if let globalHotkey {
            client.send(["hotkey": globalHotkey.description, "action": "toggle-all"])
        }
        for binding in bindings.sorted {
            client.send([
                "hotkey": binding.hotkey.description, "action": "toggle", "id": binding.id,
                "path": binding.request["path"] ?? NSNull(), "open": panels[binding.id]?.isOpen == true
            ])
        }
        client.finish()
    }
}
