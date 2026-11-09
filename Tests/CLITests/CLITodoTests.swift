import Foundation
import Testing
import TestSupport

/// Hotkeys, `toggle --all`, persisted channels and `get`: their requests,
/// output and exit codes.
@Suite struct CLITodoTests {
    private let ok = [[RecordingServer.Step.send(#"{"event":"ok"}"#)]]
    private let dir = TempDir()

    @Test func showCarriesTheHotkeyAsGiven() throws {
        let file = dir.file("todo.md", "- [ ] a\n")
        let call = try canvas(["show", file.path, "--id", "todo", "--hotkey", "ctrl+opt+t"])
        #expect(call.result.status == 0, "\(call.result.summary)")
        #expect(options(call.request)
            == #"{"cmd":"show","focus":false,"hotkey":"ctrl+opt+t","id":"todo","kind":"markdown"}"#)
        let none = try canvas(["toggle", file.path, "--hotkey", "none"])
        #expect(none.request["hotkey"] as? String == "none")
    }

    @Test func anEmptyHotkeyIsAUsageError() throws {
        let file = dir.file("todo.md", "- [ ] a\n")
        let call = try canvas(["show", file.path, "--hotkey", ""])
        #expect(call.result.status == 64)
        #expect(call.connections.isEmpty)
    }

    @Test func aRejectedHotkeyExitsOne() throws {
        let file = dir.file("todo.md", "- [ ] a\n")
        let call = try canvas(["show", file.path, "--hotkey", "ctrl+t"],
                              replies: [[.send(#"{"event":"error","message":"hotkey ctrl+t is already used"}"#)]])
        #expect(call.result.status == 1)
        #expect(call.result.stderr.contains("already used"))
    }

    @Test func toggleAllNeedsNoFileAndTakesNothingElse() throws {
        let shown = try canvas(["toggle", "--all"], replies: [[.send(#"{"event":"shown"}"#)]])
        #expect(shown.result.status == 0, "\(shown.result.summary)")
        #expect(canonical(shown.request) == #"{"all":true,"cmd":"toggle"}"#)
        let hidden = try canvas(["toggle", "--all"], replies: [[.send(#"{"event":"hidden"}"#)]])
        #expect(hidden.result.status == 0)
        let extra = try canvas(["toggle", "--all", "--id", "x"])
        #expect(extra.result.status == 64)
        #expect(extra.connections.isEmpty)
    }

    @Test func toggleAllWithNoServerExitsZero() throws {
        let home = TempDir()
        let result = try ChildProcess.run(Repo.cli, ["toggle", "--all"],
                                          environment: ["CANVAS_HOME": home.path, "CANVAS_NO_AUTOSTART": "1"])
        #expect(result.status == 0, "\(result.summary)")
    }

    @Test func hotkeysPrintsEachLine() throws {
        let lines = [#"{"hotkey":"ctrl+opt+space","action":"toggle-all"}"#,
                     #"{"hotkey":"ctrl+opt+t","action":"toggle","id":"todo","path":null,"open":false}"#]
        let call = try canvas(["hotkeys"], replies: [lines.map { .send($0) }])
        #expect(canonical(call.request) == #"{"cmd":"hotkeys"}"#)
        #expect(call.result.stdout == lines.joined(separator: "\n") + "\n")
        #expect(try canvas(["hotkeys", "x"]).result.status == 64)
    }

    @Test func pubPersistAndClear() throws {
        let persist = try canvas(["pub", "todo.items", "[1]", "--persist"], replies: ok)
        #expect(persist.result.status == 0, "\(persist.result.summary)")
        #expect(persist.raw == #"{"cmd":"pub","channel":"todo.items","persist":true,"value":[1]}"#)
        let clear = try canvas(["pub", "todo.items", "--clear"], replies: ok)
        #expect(clear.result.status == 0, "\(clear.result.summary)")
        #expect(clear.raw == #"{"cmd":"pub","channel":"todo.items","op":"clear"}"#)
    }

    @Test(arguments: [["pub", "a", "--clear", "1"], ["pub", "a", "--clear", "--merge"],
                      ["pub", "a", "--clear", "--persist"], ["pub", "a", "--clear", "--keep", "3"],
                      ["pub", "canvas.x", "--clear"]])
    func clearTakesOnlyAChannel(args: [String]) throws {
        let call = try canvas(args, replies: ok)
        #expect(call.result.status == 64, "\(args)")
        #expect(call.connections.isEmpty)
    }

    @Test func getPrintsTheValueOrExitsOne() throws {
        let call = try canvas(["get", "todo.items"], replies: [[.send(#"{"event":"value","value":[{"a":1}]}"#)]])
        #expect(call.result.status == 0, "\(call.result.summary)")
        #expect(call.raw == #"{"cmd":"get","channel":"todo.items"}"#)
        #expect(call.result.stdout == "[{\"a\":1}]\n")
        let missing = try canvas(["get", "todo.items"],
                                 replies: [[.send(#"{"event":"error","message":"channel todo.items has no value"}"#)]])
        #expect(missing.result.status == 1)
        #expect(missing.result.stderr.contains("no value"))
    }

    @Test(arguments: [["get"], ["get", "Bad"], ["get", "a", "b"], ["get", "--history", "a"]])
    func getNeedsOneValidChannel(args: [String]) throws {
        let call = try canvas(args)
        #expect(call.result.status == 64, "\(args)")
        #expect(call.connections.isEmpty)
    }
}
