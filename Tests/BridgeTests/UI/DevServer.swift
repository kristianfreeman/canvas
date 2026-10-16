import CanvasCore
import Foundation
import Testing
import TestSupport

/// A debug `canvas-server serve` on its own CANVAS_HOME, with `eval`
/// enabled and no warm page, plus the CLI pointed at it. Its panels appear
/// on screen.
final class DevServer {
    let home = TempDir()
    private let process: ChildProcess

    init() throws {
        let config = home.file("config.toml", "warm = \"never\"\n")
        try #require(FileManager.default.isExecutableFile(atPath: Repo.server.path), "build canvas-server first")
        process = try ChildProcess(Repo.server, ["serve"], environment: [
            "CANVAS_HOME": home.path, "CANVAS_TEST": "1", "CANVAS_WEB_DIR": Repo.webDir.path,
            "CANVAS_CONFIG": config.path
        ])
        let deadline = Date().addingTimeInterval(5)
        while try cli(["ping"]).status != 0 {
            guard Date() < deadline else { throw BridgeTimeout(description: "the dev server did not start") }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private var environment: [String: String] {
        ["CANVAS_HOME": home.path, "CANVAS_NO_AUTOSTART": "1"]
    }

    func cli(_ args: [String], stdin: Data? = nil, timeout: TimeInterval = 10) throws -> ProcessResult {
        try ChildProcess.run(Repo.cli, args, environment: environment, stdin: stdin, timeout: timeout)
    }

    /// A CLI call left running, for `--wait` and `sub`.
    func start(_ args: [String]) throws -> ChildProcess {
        try ChildProcess(Repo.cli, args, environment: environment)
    }

    /// The ids `canvas list` reports.
    func listed() throws -> [String] {
        try cli(["list"]).stdout.split(separator: "\n").compactMap { line in
            (JSON.decode(Data(line.utf8)) as? [String: Any])?["id"] as? String
        }
    }

    func waitListed(_ id: String) throws {
        let deadline = Date().addingTimeInterval(5)
        while try !listed().contains(id) {
            guard Date() < deadline else { throw BridgeTimeout(description: "\(id) never showed up in list") }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// Panel id to the renderer `canvas list` reports for it.
    func renderers() throws -> [String: String] {
        let entries = try cli(["list"]).stdout.split(separator: "\n").compactMap { line in
            JSON.decode(Data(line.utf8)) as? [String: Any]
        }
        return Dictionary(entries.compactMap { entry in
            guard let id = entry["id"] as? String, let renderer = entry["renderer"] as? String else { return nil }
            return (id, renderer)
        }) { $1 }
    }

    func waitRenderer(_ id: String, _ renderer: String) throws {
        let deadline = Date().addingTimeInterval(5)
        while try renderers()[id] != renderer {
            guard Date() < deadline else { throw BridgeTimeout(description: "\(id) never used \(renderer)") }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// The note of the server's latest `show` trace record.
    func lastNote() throws -> String? {
        let event = try request(["cmd": "trace"])
        let records = event["stages"] as? [[String: Any]] ?? []
        return records.last { $0["cmd"] as? String == "show" }?["note"] as? String
    }

    /// Runs `js` as an async function body in panel `id` (`eval` request).
    /// In a native panel it runs as a function body in its JS context.
    func eval(_ id: String, _ js: String) throws -> Any? {
        let event = try request(["cmd": "eval", "id": id, "js": js])
        try #require(event["event"] as? String == "value", "eval answered \(event)")
        return event["value"]
    }

    private func request(_ object: [String: Any]) throws -> [String: Any] {
        let fd = try #require(Sock.connect(to: home.url.appendingPathComponent("canvas.sock").path))
        defer { close(fd) }
        Sock.writeLine(fd, object)
        guard case .line(let line) = LineReader(fd: fd).next(deadline: Date().addingTimeInterval(5)) else { return [:] }
        return JSON.decode(line) as? [String: Any] ?? [:]
    }

    deinit {
        _ = try? cli(["hide", "--all"])
        process.signal(SIGTERM)
        _ = process.wait(timeout: 5)
    }
}
