import Foundation

public enum Paths {
    /// The home directory: socket, lock, remembered frames and log.
    /// `CANVAS_HOME` overrides it.
    public static let support: URL = {
        let url = home(environment: ProcessInfo.processInfo.environment)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    public static func home(environment: [String: String]) -> URL {
        if let dir = environment["CANVAS_HOME"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Canvas", isDirectory: true)
    }

    public static var socket: String { support.appendingPathComponent("canvas.sock").path }
    public static var lock: String { support.appendingPathComponent("server.lock").path }
    public static var frames: String { support.appendingPathComponent("frames.json").path }
    public static var log: String { support.appendingPathComponent("server.log").path }

    /// `CANVAS_CONFIG` overrides it.
    public static var config: URL {
        if let path = ProcessInfo.processInfo.environment["CANVAS_CONFIG"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/canvas/config.toml")
    }

    /// This binary, with symlinks resolved. argv[0] is just "canvas" when
    /// run from PATH, so ask dyld instead.
    public static var executable: URL {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        _NSGetExecutablePath(&buffer, &size)
        return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
    }

    /// The .app bundle this binary lives in, if any. The CLI is usually a
    /// symlink to Canvas.app/Contents/MacOS/canvas.
    public static var appBundle: URL? {
        let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return bundle.pathExtension == "app" ? bundle : nil
    }

    /// The built web renderer. CANVAS_WEB_DIR overrides it for development.
    public static var webDir: URL {
        if let dir = ProcessInfo.processInfo.environment["CANVAS_WEB_DIR"] {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        if let resources = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: resources.appendingPathComponent("web/index.html").path) {
            return resources.appendingPathComponent("web", isDirectory: true)
        }
        var dir = executable.deletingLastPathComponent()
        for _ in 0..<5 {
            let candidate = dir.appendingPathComponent("web/dist", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("index.html").path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        return dir.appendingPathComponent("web/dist", isDirectory: true)
    }
}
