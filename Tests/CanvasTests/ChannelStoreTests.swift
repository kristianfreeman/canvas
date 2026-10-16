import CanvasCore
import Foundation
import Testing

private func ints(_ values: [Any]) -> [Int] {
    values.compactMap { ($0 as? NSNumber)?.intValue }
}

/// Collects what a subscriber hears.
private final class Recorder {
    var updates: [ChannelUpdate] = []
    func callback(_ update: ChannelUpdate) { updates.append(update) }
}

@Suite struct ChannelStoreValueTests {
    @Test func setReplacesLatestAndAppendsHistory() throws {
        let store = ChannelStore()
        try store.publish(ChannelMessage(channel: "load", value: 1))
        try store.publish(ChannelMessage(channel: "load", value: json(#"{"x":2}"#)))
        #expect(canonical(store.latest("load")) == #"{"x":2}"#)
        #expect(canonical(store.history("load")) == #"[1,{"x":2}]"#)
        #expect(store.latest("other") == nil)
        #expect(store.history("other").isEmpty)
    }

    @Test func mergeAppliesAPatchToLatest() throws {
        let store = ChannelStore()
        try store.publish(ChannelMessage(channel: "state", value: json(#"{"a":1,"b":{"c":2,"d":3}}"#)))
        let merged = try store.publish(
            ChannelMessage(channel: "state", value: json(#"{"b":{"c":null},"e":4}"#), op: .merge))
        let expected = #"{"a":1,"b":{"d":3},"e":4}"#
        #expect(canonical(merged) == expected)
        #expect(canonical(store.latest("state")) == expected)
        #expect(canonical(store.history("state").last) == expected)
        #expect(store.history("state").count == 2)
    }

    @Test func mergeOnANewChannelStartsFromNothing() throws {
        let store = ChannelStore()
        try store.publish(ChannelMessage(channel: "fresh", value: json(#"{"a":null,"b":1}"#), op: .merge))
        #expect(canonical(store.latest("fresh")) == #"{"b":1}"#)
    }

    @Test func historyDefaultsTo120AndDropsOldestFirst() throws {
        let store = ChannelStore()
        for value in 0..<150 { try store.publish(ChannelMessage(channel: "n", value: value)) }
        #expect(ChannelStore.defaultCapacity == 120)
        #expect(store.capacity("n") == 120)
        #expect(ints(store.history("n")) == Array(30..<150))
    }

    @Test func keepShrinksToTheNewestValues() throws {
        let store = ChannelStore()
        for value in 0..<10 { try store.publish(ChannelMessage(channel: "n", value: value)) }
        try store.publish(ChannelMessage(channel: "n", value: 10, keep: 3))
        #expect(store.capacity("n") == 3)
        #expect(ints(store.history("n")) == [8, 9, 10])
        try store.publish(ChannelMessage(channel: "n", value: 11))
        #expect(ints(store.history("n")) == [9, 10, 11])
    }

    @Test func keepGrowsWithoutLosingHistory() throws {
        let store = ChannelStore()
        for value in 0..<3 { try store.publish(ChannelMessage(channel: "n", value: value, keep: 2)) }
        for value in 3..<6 { try store.publish(ChannelMessage(channel: "n", value: value, keep: 4)) }
        #expect(ints(store.history("n")) == [2, 3, 4, 5])
    }

    @Test func keepZeroTurnsHistoryOff() throws {
        let store = ChannelStore()
        let recorder = Recorder()
        _ = try store.subscribe("n", recorder.callback)
        try store.publish(ChannelMessage(channel: "n", value: 1))
        try store.publish(ChannelMessage(channel: "n", value: 2, keep: 0))
        try store.publish(ChannelMessage(channel: "n", value: 3))
        #expect(store.history("n").isEmpty)
        #expect(canonical(store.latest("n")) == "3")
        #expect(recorder.updates.map { $0.appended.count } == [1, 0, 0])
        #expect(ints(recorder.updates.map(\.value)) == [1, 2, 3])
    }

    @Test func negativeKeepIsRejected() {
        let store = ChannelStore()
        #expect(throws: ChannelError.self) { try store.publish(ChannelMessage(channel: "n", value: 1, keep: -1)) }
        #expect(store.latest("n") == nil)
    }
}

@Suite struct ChannelStoreSubscriberTests {
    @Test func subscribersHearLatestAndAppended() throws {
        let store = ChannelStore()
        let first = Recorder()
        let second = Recorder()
        let other = Recorder()
        _ = try store.subscribe("a", first.callback)
        _ = try store.subscribe("a", second.callback)
        _ = try store.subscribe("b", other.callback)
        try store.publish(ChannelMessage(channel: "a", value: json(#"{"x":1}"#)))
        try store.publish(ChannelMessage(channel: "a", value: json(#"{"y":2}"#), op: .merge))
        for recorder in [first, second] {
            #expect(recorder.updates.map(\.channel) == ["a", "a"])
            #expect(canonical(recorder.updates.last?.value) == #"{"x":1,"y":2}"#)
            #expect(canonical(recorder.updates.last?.appended) == #"[{"x":1,"y":2}]"#)
        }
        #expect(other.updates.isEmpty)
    }

    @Test func unsubscribedCallbacksStop() throws {
        let store = ChannelStore()
        let kept = Recorder()
        let dropped = Recorder()
        _ = try store.subscribe("a", kept.callback)
        let id = try store.subscribe("a", dropped.callback)
        #expect(store.subscriberCount("a") == 2)
        store.unsubscribe(id)
        #expect(store.subscriberCount("a") == 1)
        try store.publish(ChannelMessage(channel: "a", value: 1))
        #expect(kept.updates.count == 1)
        #expect(dropped.updates.isEmpty)
    }

    @Test func rejectedPublishNotifiesNobody() throws {
        let store = ChannelStore()
        let recorder = Recorder()
        _ = try store.subscribe("canvas.sys.cpu", recorder.callback)
        #expect(throws: ChannelError.self) {
            try store.publish(ChannelMessage(channel: "canvas.sys.cpu", value: 1))
        }
        #expect(recorder.updates.isEmpty)
        try store.publish(ChannelMessage(channel: "canvas.sys.cpu", value: 0.5), from: .server)
        #expect(recorder.updates.count == 1)
    }
}

@Suite struct ChannelNameTests {
    @Test(arguments: ["top", "top.select", "a-b_c.0", "canvas.sys.cpu", "x.y.z.w", "9"])
    func validNames(_ name: String) {
        #expect(ChannelStore.isValidName(name))
    }

    @Test(arguments: ["", ".", "a.", ".a", "a..b", "Top", "top select", "tøp", "a/b", "a:b", "a.B"])
    func invalidNames(_ name: String) throws {
        #expect(!ChannelStore.isValidName(name))
        let store = ChannelStore()
        #expect(throws: ChannelError.self) { try store.publish(ChannelMessage(channel: name, value: 1)) }
        #expect(throws: ChannelError.self) { try store.subscribe(name) { _ in } }
    }

    @Test func reservedPrefixIsServerOnly() throws {
        let store = ChannelStore()
        #expect(ChannelStore.isReserved("canvas.sys.cpu"))
        #expect(!ChannelStore.isReserved("canvasx.cpu"))
        #expect(!ChannelStore.isReserved("my.canvas.cpu"))
        #expect(throws: ChannelError.self) {
            try store.publish(ChannelMessage(channel: "canvas.anything", value: 1))
        }
        try store.publish(ChannelMessage(channel: "canvasx.cpu", value: 1))
        try store.publish(ChannelMessage(channel: "canvas.sys.cpu", value: 1), from: .server)
        #expect(canonical(store.latest("canvas.sys.cpu")) == "1")
        _ = try store.subscribe("canvas.sys.cpu") { _ in }
    }
}
