import AppKit
import CanvasCore

/// `canvas-server` with no arguments (how launchd and `open` start it) or
/// `serve` runs the panel server. The CLI is the separate C binary.
public enum Entry {
    public static func run(_ args: [String]) -> Never {
        guard args.isEmpty || args == ["serve"] else {
            FileHandle.standardError.write(Data("usage: canvas-server [serve]\n".utf8))
            exit(64)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
        exit(0)
    }
}
