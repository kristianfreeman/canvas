import Foundation
import Testing
import TestSupport

/// The request line the CLI writes for each command and its flags.
@Suite struct CLIRequestTests {
    private let dir = TempDir()

    @Test func showSendsTheFileWithItsKindPathAndTitleAndNothingElse() throws {
        let file = dir.file("notes.md", "# Notes\n")
        let call = try canvas(["show", file.path])
        #expect(call.result.status == 0, "\(call.result.summary)")
        #expect(call.request["source"] as? String == "# Notes\n")
        #expect(call.request["path"] as? String == file.path)
        #expect(call.request["title"] as? String == "notes.md")
        #expect(options(call.request) == #"{"cmd":"show","focus":false,"kind":"markdown"}"#)
    }

    @Test(arguments: [
        ("view.tsx", "tsx"), ("view.JSX", "tsx"), ("view.ts", "tsx"),
        ("notes.md", "markdown"), ("notes.txt", "markdown")
    ])
    func aFilesKindFollowsItsExtension(name: String, kind: String) throws {
        let call = try canvas(["show", dir.file(name, "export default () => null").path])
        #expect(call.request["kind"] as? String == kind)
    }

    @Test(arguments: [
        ("export default () => <p/>", [String](), "tsx"),
        ("# Just *markdown*", [], "markdown"),
        ("export default 1", ["--kind", "md"], "markdown"),
        ("# hi", ["--kind", "jsx"], "tsx")
    ])
    func stdinIsSniffedForADefaultExportUnlessKindIsGiven(source: String, flags: [String], kind: String) throws {
        let call = try canvas(["show"] + flags, stdin: Data(source.utf8))
        #expect(call.request["source"] as? String == source)
        #expect(call.request["kind"] as? String == kind)
        #expect(call.request["path"] == nil && call.request["title"] == nil)
    }

    @Test func dataComesInlineFromAFileOrFromStdinMinified() throws {
        let file = dir.file("view.tsx", "export default () => null")
        let props = dir.file("props.json", "{ \"rows\": [1, 2] }\n")
        let inline = try canvas(["show", file.path, "--data", #"{"n": 1}"#])
        #expect(canonical(inline.request["data"]) == #"{"n":1}"#)
        let fromFile = try canvas(["show", file.path, "--data", props.path])
        #expect(fromFile.raw.contains(#""data":{"rows":[1,2]}"#))
        let fromStdin = try canvas(["show", file.path, "--data", "-"], stdin: Data("[true, null]\n".utf8))
        #expect(fromStdin.raw.contains(#""data":[true,null]"#))
        let scalar = try canvas(["show", file.path, "--data", "42"])
        #expect(scalar.raw.contains(#""data":42"#))
    }

    @Test func placementFlagsBecomeTypedMembers() throws {
        let call = try canvas([
            "show", dir.file("a.md", "a").path, "--position", "top-right", "--screen", "main", "--margin", "0",
            "--width", "50%", "--height", "300", "--min-height", "120", "--max-height", "80%", "--no-resizable",
            "--level", "top", "--spaces", "current", "--pin", "--click-through", "--opacity", "0.5",
            "--stack", "hud", "--forget"
        ])
        #expect(options(call.request) == """
            {"clickThrough":true,"cmd":"show","focus":false,"forget":true,"height":300,"kind":"markdown",\
            "level":"top","margin":0,"maxHeight":"80%","minHeight":120,"opacity":0.5,"pin":true,\
            "position":"top-right","resizable":false,"screen":"main","spaces":"current","stack":"hud","width":"50%"}
            """)
    }

    @Test func atKeepsTheSignOfNegativeZeroSoItMeansTheFarEdge() throws {
        let call = try canvas(["show", dir.file("a.md", "a").path, "--at", "-0,50%"])
        #expect(call.raw.contains(#""at":{"x":-0.0,"y":"50%"}"#), "\(call.raw)")
        let plain = try canvas(["show", dir.file("b.md", "b").path, "--at", "24,-10%"])
        #expect(plain.raw.contains(#""at":{"x":24,"y":"-10%"}"#), "\(plain.raw)")
    }

    @Test func waitSendsButtonsAndFocusButKeepsTheTimeoutLocal() throws {
        let call = try canvas(
            ["show", dir.file("a.md", "a").path, "--wait", "--buttons", " Approve , Reject,", "--timeout", "5"],
            replies: [[.send(rendered), .send(#"{"event":"result","value":"Approve"}"#)]])
        #expect(options(call.request) == """
            {"buttons":["Approve","Reject"],"cmd":"show","focus":true,"kind":"markdown","wait":true}
            """)
    }

    @Test func toggleFocusesByDefaultAndNoFocusOverrides() throws {
        let file = dir.file("a.md", "a")
        let toggle = try canvas(["toggle", file.path, "--id", "keys"])
        #expect(options(toggle.request) == #"{"cmd":"toggle","focus":true,"id":"keys","kind":"markdown"}"#)
        let quiet = try canvas(["toggle", file.path, "--no-focus"])
        #expect(quiet.request["focus"] as? Bool == false)
    }

    @Test func hideDefaultsToTheDefaultIdOrTakesAll() throws {
        let hidden = [[RecordingServer.Step.send(#"{"event":"hidden"}"#)]]
        #expect(canonical(try canvas(["hide"], replies: hidden).request) == #"{"cmd":"hide","id":"default"}"#)
        #expect(canonical(try canvas(["hide", "--all"], replies: hidden).request) == #"{"all":true,"cmd":"hide"}"#)
    }

    @Test func moveAndUpdateNameThePanel() throws {
        let moved = #"{"event":"moved","frame":{"x":1,"y":2,"width":3,"height":4}}"#
        let move = try canvas(["move", "--id", "hud", "--at", "10,-24", "--width", "320"], replies: [[.send(moved)]])
        #expect(canonical(move.request) == #"{"at":{"x":10,"y":-24},"cmd":"move","id":"hud","width":320}"#)
        let update = try canvas(
            ["update", "--id", "hud", "--data", #"{"n": [1]}"#], replies: [[.send(#"{"event":"updated"}"#)]])
        #expect(update.raw == #"{"cmd":"update","id":"hud","data":{"n":[1]}}"#)
    }
}
