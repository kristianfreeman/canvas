import CanvasCore
import Foundation
import Testing

private func pub(_ text: String) throws -> PubRequest {
    guard let object = json(text) as? [String: Any] else { fatalError("not an object: \(text)") }
    return try PubRequest(object)
}

private func sub(_ text: String) throws -> SubRequest {
    guard let object = json(text) as? [String: Any] else { fatalError("not an object: \(text)") }
    return try SubRequest(object)
}

@Suite struct ReservedNameTests {
    @Test(arguments: ["canvas", "canvas.sys.cpu", "canvas.sys.anything", "canvas.ui"])
    func externalPublishersCannotUseReservedNames(_ name: String) throws {
        #expect(throws: ChannelError.self) { try ChannelStore.validate(name) }
        #expect(throws: ChannelError.self) { try pub(#"{"channel":"\#(name)","value":1}"#) }
        try ChannelStore.validate(name, from: .server)
    }

    @Test(arguments: ["top.select", "canvasx", "my.canvas.sys"])
    func otherNamesArePublishable(_ name: String) throws {
        try ChannelStore.validate(name)
        #expect(try pub(#"{"channel":"\#(name)","value":1}"#).channel == name)
    }

    @Test func theServerStillValidatesTheShapeOfReservedNames() {
        #expect(throws: ChannelError.self) { try ChannelStore.validate("canvas.Sys", from: .server) }
    }
}

@Suite struct PubRequestTests {
    @Test func defaultsToSetWithNoKeep() throws {
        let request = try pub(#"{"channel":"load","value":{"a":1}}"#)
        #expect(request.op == .set)
        #expect(request.keep == nil)
        #expect(!request.stream)
        #expect(canonical(request.value) == #"{"a":1}"#)
    }

    @Test func mergeAndKeepCarryIntoTheMessage() throws {
        let request = try pub(#"{"channel":"state","value":1,"op":"merge","keep":5}"#)
        let message = request.message(2)
        #expect(message.op == .merge)
        #expect(message.keep == 5)
        #expect(canonical(message.value) == "2")
    }

    @Test func aStreamResizesTheHistoryOnlyWithItsFirstValue() throws {
        let request = try pub(#"{"channel":"feed","stream":true,"keep":3}"#)
        #expect(request.stream)
        #expect(request.message(1, first: true).keep == 3)
        #expect(request.message(2, first: false).keep == nil)
    }

    @Test func aNullValueIsAValue() throws {
        #expect(try pub(#"{"channel":"x","value":null}"#).value is NSNull)
    }

    @Test(arguments: [
        #"{"value":1}"#,
        #"{"channel":"x"}"#,
        #"{"channel":"x","value":1,"op":"append"}"#,
        #"{"channel":"x","value":1,"keep":-1}"#,
        #"{"channel":"x","value":1,"keep":2.5}"#,
        #"{"channel":"x","value":1,"keep":true}"#,
        #"{"channel":"x","value":1,"keep":"3"}"#,
        #"{"channel":"Bad Name","value":1}"#
    ])
    func malformedRequestsAreRejected(_ text: String) {
        #expect(throws: ChannelError.self) { try pub(text) }
    }
}

@Suite struct SubRequestTests {
    @Test func keepsTheGivenOrderAndDropsDuplicates() throws {
        let request = try sub(#"{"channels":["b","a","b","canvas.sys.cpu"],"history":true}"#)
        #expect(request.channels == ["b", "a", "canvas.sys.cpu"])
        #expect(request.history)
    }

    @Test(arguments: [#"{}"#, #"{"channels":[]}"#, #"{"channels":["ok","Not OK"]}"#, #"{"channels":[1]}"#])
    func malformedRequestsAreRejected(_ text: String) {
        #expect(throws: ChannelError.self) { try sub(text) }
    }

    @Test func replayFollowsRequestOrderWithValuesOldestFirst() throws {
        let store = ChannelStore()
        try store.publish(ChannelMessage(channel: "b", value: "b1"))
        try store.publish(ChannelMessage(channel: "a", value: "a1"))
        try store.publish(ChannelMessage(channel: "b", value: "b2"))
        try store.publish(ChannelMessage(channel: "a", value: "a2"))
        let request = try sub(#"{"channels":["a","empty","b"],"history":true}"#)
        let expected = [
            #"{"channel":"a","event":"history","values":["a1","a2"]}"#,
            #"{"channel":"b","event":"history","values":["b1","b2"]}"#
        ]
        #expect(request.replay(from: store).map(canonical) == expected)
    }

    @Test func replaySkipsChannelsWithHistoryOffAndAllOfItWithoutTheFlag() throws {
        let store = ChannelStore()
        try store.publish(ChannelMessage(channel: "quiet", value: 1, keep: 0))
        try store.publish(ChannelMessage(channel: "loud", value: 1))
        #expect(try sub(#"{"channels":["quiet"],"history":true}"#).replay(from: store).isEmpty)
        #expect(try sub(#"{"channels":["loud"]}"#).replay(from: store).isEmpty)
        #expect(try sub(#"{"channels":["loud"],"history":true}"#).replay(from: store).count == 1)
    }
}
