import CanvasCore
import Foundation
import Testing

@Suite struct ShowRequestTests {
    @Test func missingSourceIsAnError() {
        #expect(throws: RequestError.self) { try ShowRequest(["cmd": "show", "id": "x"]) }
        #expect(throws: RequestError.self) { try ShowRequest(["source": 42]) }
        do {
            _ = try ShowRequest([:])
        } catch {
            #expect(error.message == "missing source")
        }
    }

    @Test(arguments: [
        ([String: Any](), "default"),
        (["id": ""], "default"),
        (["id": 42], "default"),
        (["id": NSNull()], "default"),
        (["id": "cheatsheet"], "cheatsheet")
    ] as [([String: Any], String)])
    func idFallsBackToDefault(fields: [String: Any], expected: String) throws {
        #expect(try showRequest(fields).id == expected)
        #expect(ShowRequest.id(in: fields) == expected)
    }

    @Test(arguments: [
        (nil, "markdown"),
        ("markdown", "markdown"),
        ("tsx", "tsx"),
        ("md", "markdown"),
        ("TSX", "markdown"),
        ("html", "markdown")
    ] as [(String?, String)])
    func kindIsTsxOrMarkdown(kind: String?, expected: String) throws {
        var fields: [String: Any] = [:]
        fields["kind"] = kind
        #expect(try showRequest(fields).kind == expected)
    }

    @Test func defaultsWhenOnlySourceIsGiven() throws {
        let request = try ShowRequest(["source": "# hi"])
        #expect(request.source == "# hi")
        #expect(!request.wait)
        #expect(!request.focus)
        #expect(!request.trace)
        #expect(request.theme == nil)
        #expect(request.placement == Placement() && request.placement.given.isEmpty)
        #expect(request.placement.restoresRememberedFrame)
        #expect(request.data == nil && request.buttons == nil && request.path == nil && request.title == nil)
    }

    @Test func readsEveryField() throws {
        let request = try ShowRequest([
            "source": "x", "path": "/tmp/a.md", "title": "A", "buttons": ["Approve", "Reject"],
            "wait": true, "focus": true, "trace": true, "width": 640, "height": 480.5,
            "position": "right", "theme": "light"
        ])
        #expect(request.path == "/tmp/a.md")
        #expect(request.title == "A")
        #expect(request.buttons == ["Approve", "Reject"])
        #expect(request.wait && request.focus && request.trace)
        #expect(request.placement.width == .points(640))
        #expect(request.placement.height == .points(480.5))
        #expect(request.placement.position == .right)
        #expect(request.placement.given == [.width, .height, .position])
        #expect(!request.placement.restoresRememberedFrame)
        #expect(request.theme == .light)
    }

    @Test func readsEveryPlacementField() throws {
        let request = try showRequest([
            "position": "mouse", "width": "50%", "screen": "focused", "pin": true, "clickThrough": true,
            "opacity": 0.85, "stack": "notes", "level": "top", "spaces": "current", "resizable": false
        ])
        let placement = request.placement
        #expect(placement.position == .mouse && placement.width == .percent(50) && placement.screen == .focused)
        #expect(placement.pin && placement.clickThrough && placement.opacity == 0.85 && placement.stack == "notes")
        #expect(placement.effectiveLevel == .top && placement.effectiveSpaces == .all && !placement.resizable)
        #expect(!placement.closesOnEscape)
    }

    /// Lines `canvas show --emit` prints. JSON's `-0` would decode as the
    /// integer 0 and lose "flush right", so the CLI sends `-0.0`.
    @Test func cliNegativeZeroKeepsItsSign() throws {
        let line = #"{"cmd":"show","source":"","at":{"x":-0.0,"y":"-0.0%"},"width":320,"minHeight":"10%"}"#
        let fields = try #require(JSON.decode(Data(line.utf8)) as? [String: Any])
        let placement = try ShowRequest(fields).placement
        #expect(placement.at == AtPoint(x: Length(magnitude: 0, unit: .points, negative: true),
                                        y: Length(magnitude: 0, unit: .percent, negative: true)))
        #expect(placement.minHeight == .percent(10))
        let frame = placement.placedFrame(contentHeight: 200, on: Screens.laptop, mouse: .zero)
        #expect(frame == CGRect(x: 1192, y: 0, width: 320, height: 200))
    }

    @Test func unknownThemeIsIgnored() throws {
        #expect(try showRequest(["theme": "sepia"]).theme == nil)
    }

    @Test(arguments: [
        (["position": "sideways"], "invalid position \"sideways\""),
        (["height": true], "invalid height true"),
        (["opacity": 2], "invalid opacity 2")
    ] as [([String: Any], String)])
    func invalidPlacementFailsTheRequest(fields: [String: Any], prefix: String) {
        do {
            _ = try ShowRequest(fields.merging(["source": ""]) { $1 })
            Issue.record("expected \(fields) to fail")
        } catch {
            #expect(error.message.hasPrefix(prefix), "\(error.message)")
        }
    }

    @Test func nullDataIsNoData() throws {
        #expect(try showRequest(["data": NSNull()]).data == nil)
        #expect(try showRequest(["data": NSNull()]).payload["data"] == nil)
    }

    @Test(arguments: ["0", "false", "\"\"", "[]", "{\"a\":[1,null]}"])
    func falsyDataIsKept(literal: String) throws {
        let payload = try showRequest(["data": json(literal)]).payload
        #expect(canonical(payload["data"]) == canonical(json(literal)))
    }

    @Test func minimalPayload() throws {
        let payload = try ShowRequest(["source": "s", "id": "x", "path": "/p", "focus": true]).payload
        #expect(canonical(payload) == #"{"kind":"markdown","source":"s","wait":false}"#)
    }

    @Test func fullPayload() throws {
        let payload = try ShowRequest([
            "source": "s", "kind": "tsx", "title": "T", "data": ["n": 1], "buttons": ["OK"],
            "wait": true, "theme": "dark", "trace": true, "width": 300
        ]).payload
        #expect(canonical(payload)
            == #"{"buttons":["OK"],"data":{"n":1},"kind":"tsx","source":"s","theme":"dark","title":"T","wait":true}"#)
    }
}
