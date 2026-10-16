import CanvasCore
import Foundation
import Testing
import TestSupport

/// The exit codes and outputs in docs/protocol.md, end to end: the C CLI
/// against a real server with real panels.
@Suite(.serialized, .onScreen) struct UIContractTests {
    private let server: DevServer
    private let markdown: String
    private let tsx: String

    init() throws {
        server = try DevServer()
        markdown = server.home.file("note.md", "# Note\n\nHello.").path
        tsx = server.home.file("count.tsx", """
            export default function Count({ data }) { return <p id="n">{String(data?.n ?? 'none')}</p> }
            """).path
    }

    @Test func showRendersMarkdownAndTsxAndReportsABadTsx() throws {
        #expect(try server.cli(["show", markdown, "--id", "md"]).status == 0)
        #expect(try server.cli(["show", tsx, "--id", "tsx"]).status == 0)
        let bad = server.home.file("bad.tsx", "export default function Bad() { return <div> }").path
        let result = try server.cli(["show", bad, "--id", "bad"])
        #expect(result.status == 1)
        #expect(!result.stderr.isEmpty)
    }

    @Test func aWaitingCallerExitsTwoWhenThePanelIsHidden() throws {
        let waiting = try server.start(["show", markdown, "--id", "ask", "--wait"])
        try server.waitListed("ask")
        #expect(try server.cli(["hide", "--id", "ask"]).status == 0)
        #expect(waiting.wait().status == 2)
    }

    @Test func aWaitingCallerExitsTwoWhenItsPanelIsReplaced() throws {
        let waiting = try server.start(["show", markdown, "--id", "same", "--wait"])
        try server.waitListed("same")
        #expect(try server.cli(["show", tsx, "--id", "same"]).status == 0)
        #expect(waiting.wait().status == 2)
        #expect(try server.listed() == ["same"])
    }

    @Test func timeoutExitsThreeAndHidesThePanel() throws {
        let result = try server.cli(["show", markdown, "--id", "slow", "--wait", "--timeout", "0.5"])
        #expect(result.status == 3)
        #expect(try !server.listed().contains("slow"))
    }

    @Test func toggleShowsThenHides() throws {
        #expect(try server.cli(["toggle", markdown, "--id", "keys", "--no-focus"]).status == 0)
        #expect(try server.listed().contains("keys"))
        #expect(try server.cli(["toggle", markdown, "--id", "keys", "--no-focus"]).status == 0)
        #expect(try !server.listed().contains("keys"))
    }

    @Test func updateReplacesDataAndFailsForAMissingPanel() throws {
        #expect(try server.cli(["show", tsx, "--id", "live", "--data", #"{"n":1}"#]).status == 0)
        #expect(try server.eval("live", "return document.getElementById('n').textContent") as? String == "1")
        #expect(try server.cli(["update", "--id", "live", "--data", #"{"n":2}"#]).status == 0)
        #expect(try server.eval("live", "return document.getElementById('n').textContent") as? String == "2")
        let missing = try server.cli(["update", "--id", "nope", "--data", "1"])
        #expect(missing.status == 1)
        #expect(missing.stderr.contains("nope"))
    }

    @Test func aFooterButtonPressPrintsItsLabel() throws {
        let waiting = try server.start(["show", tsx, "--id", "pick", "--wait", "--buttons", "Approve,Reject"])
        try server.waitListed("pick")
        _ = try server.eval("pick", "document.querySelector('[data-canvas-primary]').click(); return true")
        let result = waiting.wait()
        #expect(result.status == 0, "\(result.summary)")
        #expect(result.stdout == "\"Approve\"\n")
    }

    // MARK: Native rendering

    @Test func listShowsWhichRendererDrawsEachPanel() throws {
        let kit = server.home.file("kit.tsx", """
            import { Card, Text } from 'canvas'
            export default function Kit() { return <Card title="Kit"><Text>native</Text></Card> }
            """).path
        #expect(try server.cli(["show", markdown, "--id", "md"]).status == 0)
        #expect(try server.cli(["show", kit, "--id", "kit"]).status == 0)
        #expect(try server.cli(["show", tsx, "--id", "dom"]).status == 0)
        #expect(try server.renderers() == ["md": "native", "kit": "native", "dom": "web"])
    }

    @Test func aDomTsxFallsBackAndTheNextShowGoesStraightToWebKit() throws {
        let first = try server.cli(["show", tsx, "--id", "dom", "--data", #"{"n":1}"#, "--trace"])
        #expect(first.status == 0, "\(first.summary)")
        #expect(try server.lastNote()?.hasSuffix("route=fallback") == true)
        #expect(try server.cli(["hide", "--id", "dom"]).status == 0)
        #expect(try server.cli(["show", tsx, "--id", "dom", "--data", #"{"n":2}"#]).status == 0)
        #expect(try server.lastNote()?.hasSuffix("route=web") == true)
        #expect(try server.eval("dom", "return document.getElementById('n').textContent") as? String == "2")
    }

    @Test func aLiveEditThatDropsTheDomGoesBackToNative() throws {
        let file = server.home.file("edit.tsx", "export default function Edit() { return <p>dom</p> }")
        #expect(try server.cli(["show", file.path, "--id", "edit"]).status == 0)
        #expect(try server.renderers()["edit"] == "web")
        try Data("import { Text } from 'canvas'\nexport default function Edit() { return <Text>kit</Text> }".utf8)
            .write(to: file)
        try server.waitRenderer("edit", "native")
    }

    @Test func aNativeFooterResultReachesTheWaitingCaller() throws {
        let waiting = try server.start(["show", markdown, "--id", "ask", "--wait", "--buttons", "Approve,Reject"])
        try server.waitListed("ask")
        #expect(try server.renderers()["ask"] == "native")
        _ = try server.eval("ask", "__post({ type: 'result', value: 'Approve' }); return true")
        let result = waiting.wait()
        #expect(result.status == 0, "\(result.summary)")
        #expect(result.stdout == "\"Approve\"\n")
    }

    @Test func updateReachesANativePanel() throws {
        let live = server.home.file("live.tsx", """
            import { Text } from 'canvas'
            export default function Live({ data }) { return <Text>{String(data?.n ?? 'none')}</Text> }
            """).path
        #expect(try server.cli(["show", live, "--id", "nlive", "--data", #"{"n":1}"#]).status == 0)
        #expect(try server.renderers()["nlive"] == "native")
        #expect(try server.cli(["update", "--id", "nlive", "--data", #"{"n":2}"#]).status == 0)
        #expect(try server.renderers()["nlive"] == "native")
    }

    @Test func aClosedNativePanelReopensWithoutRenderingOnlyForTheSameRequest() throws {
        let args = ["show", markdown, "--id", "rest", "--data", #"{"n":1}"#]
        #expect(try server.cli(args).status == 0)
        #expect(try server.cli(["hide", "--id", "rest"]).status == 0)
        #expect(try !server.listed().contains("rest"))
        #expect(try server.cli(args).status == 0)
        #expect(try server.lastNote() == "rest")
        #expect(try server.renderers()["rest"] == "native")
        #expect(try server.cli(["hide", "--id", "rest"]).status == 0)
        #expect(try server.cli(["show", markdown, "--id", "rest", "--data", #"{"n":2}"#]).status == 0)
        #expect(try server.lastNote() != "rest")
    }

    @Test func movePrintsTheNewFrame() throws {
        #expect(try server.cli(["show", markdown, "--id", "hud", "--width", "500"]).status == 0)
        let result = try server.cli(["move", "--id", "hud", "--position", "top-left", "--width", "400"])
        #expect(result.status == 0, "\(result.summary)")
        let frame = JSON.decode(Data(result.stdout.utf8)) as? [String: Any]
        #expect(frame?["width"] as? Int == 400)
        #expect(try server.cli(["move", "--id", "gone", "--position", "top"]).status == 1)
    }

    @Test func pubAndSubRoundTrip() throws {
        #expect(try server.cli(["pub", "test.status", #"{"step":"build"}"#]).status == 0)
        #expect(try server.cli(["pub", "test.status", #"{"done":true}"#, "--merge"]).status == 0)
        let sub = try server.start(["sub", "test.status", "--history"])
        Thread.sleep(forTimeInterval: 0.3)
        #expect(try server.cli(["pub", "test.status", #"{"step":"ship"}"#]).status == 0)
        Thread.sleep(forTimeInterval: 0.3)
        sub.signal(SIGTERM)
        let lines = sub.wait().stdout.split(separator: "\n").map { canonical(JSON.decode(Data($0.utf8))) }
        #expect(lines == [#"{"step":"build"}"#, #"{"done":true,"step":"build"}"#, #"{"step":"ship"}"#])
    }
}
