import Foundation

/// A hotkey to register: the global one, or the panel hotkey of an id.
public enum HotkeyRegistration: Equatable {
    case global(Hotkey)
    case panel(id: String, hotkey: Hotkey)

    public var hotkey: Hotkey {
        switch self {
        case .global(let hotkey), .panel(_, let hotkey): hotkey
        }
    }
}

/// What changing the global hotkey from `old` to `new` registers. The
/// global hotkey wins over a panel hotkey on the same keys, so the panel
/// that held `new` goes quiet, and the panel that held `old` gets it back.
public struct GlobalHotkeySwap: Equatable {
    public let unregister: [Hotkey]
    public let register: [HotkeyRegistration]

    public init(from old: Hotkey?, to new: Hotkey?, bindings: HotkeyBindings) {
        guard old != new else {
            unregister = []
            register = []
            return
        }
        var steps: [HotkeyRegistration] = []
        if let old, let panel = bindings.binding(for: old) { steps.append(.panel(id: panel.id, hotkey: old)) }
        if let new { steps.append(.global(new)) }
        unregister = old.map { [$0] } ?? []
        register = steps
    }
}

/// Watching config.toml, which may not exist yet, nor its folder.
public enum ConfigWatch {
    /// The folder to watch for `file` appearing: its own folder, or the
    /// nearest one above it that exists.
    public static func nearestFolder(of file: URL, exists: (String) -> Bool) -> URL {
        var folder = file.deletingLastPathComponent().standardizedFileURL
        while !exists(folder.path), folder.path != "/" {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }
}
