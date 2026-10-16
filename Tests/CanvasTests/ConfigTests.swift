import CanvasCore
import Foundation
import Testing

@Suite struct ConfigTests {
    @Test func defaults() {
        let config = Config()
        #expect(config.warm == .linger)
        #expect(config.idleMinutes == 10)
        #expect(config.lingerSeconds == 120)
        #expect(Config(parsing: "") == config)
    }

    @Test func readsValuesAndComments() {
        let config = Config(parsing: """
        # Canvas settings
        warm = "always"   # keep a page ready

          idle_minutes=25
        """)
        #expect(config.warm == .always)
        #expect(config.idleMinutes == 25)
    }

    @Test func commentsCanHoldQuotesAndEquals() {
        #expect(Config(parsing: #"warm = "never" # was "idle" = default"#).warm == .never)
        #expect(Config(parsing: #"# warm = "never""#).warm == .linger)
    }

    @Test(arguments: ["0", "-1", "1.5", "ten", "\"5\""])
    func idleMinutesMustBeAPositiveInteger(_ raw: String) {
        #expect(Config(parsing: "idle_minutes = \(raw)").idleMinutes == 10)
    }

    @Test func ignoresBadLinesAndKeepsGoodOnes() {
        let config = Config(parsing: """
        warm = "idle"
        garbage
        = 3
        warm
        [section]
        warm = never
        warm = "sometimes"
        warm = "always
        idle_minutes = "5"
        idle_minutes = -1
        idle_minutes = 0
        idle_minutes = ten
        colour = "mauve"
        idle_minutes = 7
        """)
        #expect(config.warm == .idle)
        #expect(config.idleMinutes == 7)
    }

    @Test func laterLinesWin() {
        let config = Config(parsing: "warm = \"never\"\r\nwarm = \"always\"\r\nidle_minutes = 3\r\n")
        #expect(config.warm == .always)
        #expect(config.idleMinutes == 3)
    }

    @Test func loadsFromAFileOrFallsBack() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.toml")
        #expect(Config.load(from: file) == Config())
        try Data("warm = \"never\"\nidle_minutes = 2\n".utf8).write(to: file)
        let config = Config.load(from: file)
        #expect(config.warm == .never)
        #expect(config.idleMinutes == 2)
    }
}
