@testable import CanvasApp
import Foundation
import Testing

/// config.toml through every way it changes, with real files in a
/// temporary folder.
@MainActor @Suite(.serialized) struct ConfigWatcherTests {
    final class Seen {
        var texts: [String?] = []
    }

    static func waitFor(_ count: Int, in seen: Seen, _ what: String) async throws {
        let deadline = Date().addingTimeInterval(3)
        while seen.texts.count < count {
            guard Date() < deadline else {
                throw NativeTimeout(description: "timed out waiting for \(what); saw \(seen.texts)")
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    static func scratch() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("config-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func seesTheFileAndItsFolderAppearThenEveryEdit() async throws {
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(".config/canvas/config.toml")
        let seen = Seen()
        let watcher = ConfigWatcher(url: file) { seen.texts.append($0) }
        defer { watcher.stop() }

        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "hotkey = \"ctrl+opt+a\"\n".write(to: file, atomically: false, encoding: .utf8)
        try await Self.waitFor(1, in: seen, "the new file")
        #expect(seen.texts.last == "hotkey = \"ctrl+opt+a\"\n")

        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        handle.write(Data("hotkey = \"ctrl+opt+b\"\n".utf8))
        try handle.close()
        try await Self.waitFor(2, in: seen, "an edit in place")
        #expect(seen.texts.last == "hotkey = \"ctrl+opt+b\"\n")

        try "hotkey = \"ctrl+opt+c\"\n".write(to: file, atomically: true, encoding: .utf8)
        try await Self.waitFor(3, in: seen, "an atomic save")
        #expect(seen.texts.last == "hotkey = \"ctrl+opt+c\"\n")

        try FileManager.default.removeItem(at: file)
        try await Self.waitFor(4, in: seen, "the delete")
        #expect(seen.texts.last == .some(nil))
    }

    @Test func ignoresTouchesThatLeaveTheTextAlone() async throws {
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("config.toml")
        try "warm = \"never\"\n".write(to: file, atomically: false, encoding: .utf8)
        let seen = Seen()
        let watcher = ConfigWatcher(url: file) { seen.texts.append($0) }
        defer { watcher.stop() }

        try "warm = \"never\"\n".write(to: file, atomically: true, encoding: .utf8)
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(seen.texts.isEmpty)
        try "hotkey = \"f5\"\n".write(to: file, atomically: true, encoding: .utf8)
        try await Self.waitFor(1, in: seen, "a real change")
        #expect(seen.texts == ["hotkey = \"f5\"\n"])
    }
}
