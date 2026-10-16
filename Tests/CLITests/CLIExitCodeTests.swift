import Foundation
import Testing
import TestSupport

/// How the CLI turns the server's events into exit codes and output
/// (docs/protocol.md, Exit codes).
@Suite struct CLIExitCodeTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var args: [String]
        var events: [String]
        var status: Int32
        var stdout = ""
        var stderr = ""

        var testDescription: String { "\(args.joined(separator: " ")) <- \(events.joined(separator: " "))" }
    }

    private static let cases: [Case] = [
        Case(args: ["show"], events: [rendered], status: 0),
        Case(args: ["show"], events: [#"{"event":"error","message":"Unexpected token (3:4)"}"#], status: 1,
             stderr: "canvas: Unexpected token (3:4)"),
        Case(args: ["show", "--wait"], events: [rendered, #"{"event":"result","value":{"choice":"A"}}"#], status: 0,
             stdout: "{\"choice\":\"A\"}\n"),
        Case(args: ["show", "--wait", "--buttons", "OK"], events: [rendered, #"{"event":"result","value":"OK"}"#],
             status: 0, stdout: "\"OK\"\n"),
        Case(args: ["show", "--wait"], events: [rendered, #"{"event":"closed"}"#], status: 2),
        Case(args: ["show", "--wait"], events: [rendered, #"{"event":"replaced"}"#], status: 2),
        Case(args: ["show", "--wait"], events: [#"{"event":"error","message":"boom"}"#], status: 1, stderr: "boom"),
        Case(args: ["toggle"], events: [#"{"event":"hidden"}"#], status: 0),
        Case(args: ["show"], events: [], status: 1, stderr: "lost the connection"),
        Case(args: ["show"], events: ["not json"], status: 1, stderr: "bad response")
    ]

    @Test(arguments: cases)
    func showEvents(_ test: Case) throws {
        let dir = TempDir()
        let call = try canvas(
            [test.args[0], dir.file("a.md", "# A").path] + test.args.dropFirst(),
            replies: [test.events.map { .send($0) }])
        #expect(call.result.status == test.status, "\(call.result.summary)")
        #expect(call.result.stdout == test.stdout)
        if test.stderr.isEmpty {
            #expect(call.result.stderr.isEmpty)
        } else {
            #expect(call.result.stderr.contains(test.stderr), "\(call.result.stderr)")
        }
    }

    @Test func timeoutHidesThePanelOnASecondConnectionAndExitsThree() throws {
        let dir = TempDir()
        let call = try canvas(
            ["show", dir.file("a.md", "a").path, "--id", "ask", "--wait", "--timeout", "0.3"],
            replies: [[.send(rendered), .hold], [.send(#"{"event":"hidden"}"#)]])
        #expect(call.result.status == 3, "\(call.result.summary)")
        #expect(call.connections.count == 2)
        #expect(canonical(call.connections.last?.json) == #"{"cmd":"hide","id":"ask"}"#)
    }

    @Test(arguments: [
        (["update", "--id", "gone", "--data", "1"], #"{"event":"error","message":"no canvas with id gone"}"#, 1),
        (["update", "--id", "x", "--data", "1"], #"{"event":"updated"}"#, 0),
        (["hide", "--all"], #"{"event":"hidden"}"#, 0),
        (["ping"], #"{"event":"pong"}"#, 0),
        (["pub", "a", "1"], #"{"event":"error","message":"channel a: bad"}"#, 1)
    ])
    func panelCommands(args: [String], event: String, status: Int32) throws {
        let call = try canvas(args, replies: [[.send(event)]])
        #expect(call.result.status == status, "\(call.result.summary)")
        #expect(call.result.stdout.isEmpty)
    }

    @Test func movePrintsTheNewFrame() throws {
        let frame = #"{"x":10,"y":20,"width":300,"height":200}"#
        let call = try canvas(["move", "--id", "hud", "--position", "top"],
                              replies: [[.send(#"{"event":"moved","frame":"# + frame + "}")]])
        #expect(call.result.status == 0, "\(call.result.summary)")
        #expect(call.result.stdout == frame + "\n")
    }

    @Test func withoutAServerShowFailsInsteadOfStartingOne() throws {
        let dir = TempDir()
        let env = ["CANVAS_HOME": dir.path, "CANVAS_NO_AUTOSTART": "1", "CANVAS_SERVER": "/usr/bin/false"]
        let show = try ChildProcess.run(Repo.cli, ["show", dir.file("a.md", "a").path], environment: env)
        #expect(show.status == 1)
        #expect(show.stderr.contains("CANVAS_NO_AUTOSTART"), "\(show.stderr)")
        let ping = try ChildProcess.run(Repo.cli, ["ping"], environment: env)
        #expect(ping.status == 1)
        let hide = try ChildProcess.run(Repo.cli, ["hide"], environment: env)
        #expect(hide.status == 0)
    }
}
