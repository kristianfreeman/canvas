import Foundation
import Testing
import TestSupport

/// `pub` and `sub`: their requests, the stream framing and the output.
@Suite struct CLIChannelTests {
    private let ok = [[RecordingServer.Step.send(#"{"event":"ok"}"#)]]

    @Test func pubSendsOneValueWithMergeAndKeep() throws {
        let set = try canvas(["pub", "top.select", #"{"pid": 42}"#], replies: ok)
        #expect(set.result.status == 0, "\(set.result.summary)")
        #expect(set.raw == #"{"cmd":"pub","channel":"top.select","value":{"pid":42}}"#)
        let merge = try canvas(["pub", "build.status", #"{"step":null}"#, "--merge", "--keep", "5"], replies: ok)
        #expect(merge.raw == #"{"cmd":"pub","channel":"build.status","op":"merge","keep":5,"value":{"step":null}}"#)
    }

    @Test func pubDashStreamsEachValidLineAndSkipsTheRest() throws {
        let input = "1\n{ \"a\": [2, 3] }\n\nnot json\n\"done\"\n"
        let call = try canvas(
            ["pub", "progress", "-", "--keep", "0"], replies: [[.readToEnd, .send(#"{"event":"ok"}"#)]],
            stdin: Data(input.utf8))
        #expect(call.result.status == 0, "\(call.result.summary)")
        #expect(call.raw == #"{"cmd":"pub","channel":"progress","keep":0,"stream":true}"#)
        #expect(call.connections.first?.streamed == ["1", #"{"a":[2,3]}"#, #""done""#])
        #expect(call.result.stderr.contains("line 4"))
    }

    @Test(arguments: ["canvas.sys.cpu", "canvas.mine", "Bad.Name", "a..b"])
    func pubRefusesReservedAndMalformedNamesWithoutConnecting(channel: String) throws {
        let call = try canvas(["pub", channel, "1"], replies: ok)
        #expect(call.result.status == 64)
        #expect(call.connections.isEmpty)
    }

    @Test func subWithOneChannelPrintsBareValuesHistoryFirst() throws {
        let call = try canvas(["sub", "cpu", "--history"], replies: [[
            .send(#"{"event":"history","channel":"cpu","values":[0.1,{"a":1}]}"#),
            .send(#"{"event":"message","channel":"cpu","value":0.3}"#)
        ]])
        #expect(call.raw == #"{"cmd":"sub","channels":["cpu"],"history":true}"#)
        #expect(call.result.status == 0, "\(call.result.summary)")
        #expect(call.result.stdout == "0.1\n{\"a\":1}\n0.3\n")
    }

    @Test func subWithSeveralChannelsWrapsEachValueWithItsChannel() throws {
        let call = try canvas(["sub", "a", "b.c"], replies: [[
            .send(#"{"event":"message","channel":"b.c","value":[1]}"#)
        ]])
        #expect(call.raw == #"{"cmd":"sub","channels":["a","b.c"],"history":false}"#)
        #expect(call.result.stdout == "{\"channel\":\"b.c\",\"value\":[1]}\n")
    }

    @Test func subStopsWithExitOneOnAnErrorEvent() throws {
        let call = try canvas(["sub", "a"], replies: [[.send(#"{"event":"error","message":"nope"}"#)]])
        #expect(call.result.status == 1)
        #expect(call.result.stderr.contains("nope"))
    }
}
