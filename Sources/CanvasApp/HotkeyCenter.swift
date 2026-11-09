import Carbon.HIToolbox
import CanvasCore

/// Registers system-wide hotkeys with Carbon's `RegisterEventHotKey`,
/// which needs no Accessibility permission. Presses arrive on the main
/// thread through the application event target.
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private struct Entry {
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    private static let signature: OSType = 0x4356_534B // "CVSK"
    private var entries: [UInt32: Entry] = [:]
    private var tokens: [Hotkey: UInt32] = [:]
    private var nextToken: UInt32 = 0
    private var handler: EventHandlerRef?

    /// Replaces any action already registered for `hotkey`. Throws when
    /// macOS refuses the shortcut. Another app holding the same shortcut
    /// is not a refusal: macOS sends each press to every app that holds it.
    func register(_ hotkey: Hotkey, action: @escaping () -> Void) throws(HotkeyError) {
        unregister(hotkey)
        installHandler()
        nextToken += 1
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: nextToken)
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, id, GetApplicationEventTarget(),
                                         0, &ref)
        guard status == noErr, let ref else {
            throw HotkeyError(status == eventHotKeyExistsErr
                ? "hotkey \(hotkey) is already registered"
                : "could not register hotkey \(hotkey) (error \(status))")
        }
        entries[nextToken] = Entry(ref: ref, action: action)
        tokens[hotkey] = nextToken
        debugLog("hotkey \(hotkey) registered")
    }

    func unregister(_ hotkey: Hotkey) {
        guard let token = tokens.removeValue(forKey: hotkey), let entry = entries.removeValue(forKey: token) else {
            return
        }
        UnregisterEventHotKey(entry.ref)
    }

    func isRegistered(_ hotkey: Hotkey) -> Bool {
        tokens[hotkey] != nil
    }

    fileprivate func pressed(_ token: UInt32) {
        entries[token]?.action()
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotkeyPressed, 1, &spec, nil, &handler)
    }
}

/// Carbon calls this with no context, so it finds the press through the
/// shared center.
private func hotkeyPressed(_: EventHandlerCallRef?, _ event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr else { return status }
    let token = id.id
    DispatchQueue.main.async { HotkeyCenter.shared.pressed(token) }
    return noErr
}
