import CanvasCore
import Foundation

/// Paths in the checkout the tests were compiled from.
public enum Repo {
    public static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The built renderer: `CANVAS_WEB_DIR` through `Paths`, else this
    /// checkout's `web/dist`. The test runner isn't inside the checkout, so
    /// the walk up from the executable that `Paths` falls back to finds
    /// nothing here.
    public static var webDir: URL {
        guard ProcessInfo.processInfo.environment["CANVAS_WEB_DIR"] != nil else {
            return root.appendingPathComponent("web/dist", isDirectory: true)
        }
        return Paths.webDir
    }

    public static var indexURL: URL { webDir.appendingPathComponent("index.html") }

    /// The CLI `scripts/test.sh` builds; `CANVAS_TEST_CLI` overrides it.
    public static var cli: URL {
        if let path = ProcessInfo.processInfo.environment["CANVAS_TEST_CLI"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return root.appendingPathComponent(".build/cli/canvas")
    }

    /// The debug server `swift build` leaves next to the test bundle.
    public static var server: URL {
        root.appendingPathComponent(".build/debug/canvas-server")
    }

    public static var examples: URL { root.appendingPathComponent("examples", isDirectory: true) }
}

/// A fresh directory, short enough that `canvas.sock` inside it fits in
/// `sun_path`. The path is real (`/private/var/...`), as `realpath` in the
/// CLI reports it.
public final class TempDir {
    public let url: URL

    public init() {
        var template = Array((NSTemporaryDirectory() + "cv-XXXXXX").utf8CString)
        guard let made = mkdtemp(&template), let real = realpath(made, nil) else {
            fatalError("mkdtemp failed: \(errno)")
        }
        url = URL(fileURLWithPath: String(cString: real), isDirectory: true)
        free(real)
    }

    public var path: String { url.path }

    public func file(_ name: String, _ contents: String) -> URL {
        let file = url.appendingPathComponent(name)
        try? Data(contents.utf8).write(to: file)
        return file
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// A canonical encoding (sorted keys) for comparing JSON values.
public func canonical(_ value: Any?) -> String {
    guard let value else { return "<absent>" }
    let options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: options) else { return "<invalid>" }
    return data.text
}

extension Data {
    public var text: String { String(bytes: self, encoding: .utf8) ?? "<not UTF-8>" }
}
