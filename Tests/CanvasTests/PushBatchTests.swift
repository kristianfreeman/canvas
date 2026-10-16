import CanvasCore
import Foundation
import Testing

/// Publishes through a real store so the batch sees the updates a page
/// subscription would.
private final class Feed {
    let store = ChannelStore()
    var batch = PushBatch()
    var limit = ChannelStore.defaultCapacity

    func listen(_ channel: String) throws {
        _ = try store.subscribe(channel) { [unowned self] update in self.batch.add(update, limit: self.limit) }
    }

    func publish(_ channel: String, _ value: Any, keep: Int? = nil) throws {
        try store.publish(ChannelMessage(channel: channel, value: value, keep: keep))
    }

    func take() -> [String] {
        batch.take().map(canonical)
    }
}

@Suite struct PushBatchTests {
    @Test func updatesBetweenPushesCollapseToTheLatestValueAndAllAppends() throws {
        let feed = Feed()
        try feed.listen("n")
        for value in 1...3 { try feed.publish("n", value) }
        #expect(feed.take() == [#"{"channel":"n","history":[1,2,3],"value":3}"#])
        #expect(feed.batch.isEmpty)
        try feed.publish("n", 4)
        #expect(feed.take() == [#"{"channel":"n","history":[4],"value":4}"#])
    }

    @Test func aChannelWithHistoryOffSendsOnlyItsValue() throws {
        let feed = Feed()
        try feed.publish("quiet", 0, keep: 0)
        try feed.listen("quiet")
        try feed.publish("quiet", 1)
        try feed.publish("quiet", 2)
        #expect(feed.take() == [#"{"channel":"quiet","value":2}"#])
    }

    @Test func channelsKeepTheOrderTheyWereFirstQueuedIn() throws {
        let feed = Feed()
        for channel in ["b", "a", "c"] { try feed.listen(channel) }
        try feed.publish("b", 1)
        try feed.publish("a", 1)
        try feed.publish("b", 2)
        try feed.publish("c", 1)
        #expect(feed.take() == [
            #"{"channel":"b","history":[1,2],"value":2}"#,
            #"{"channel":"a","history":[1],"value":1}"#,
            #"{"channel":"c","history":[1],"value":1}"#
        ])
    }

    @Test func theFirstPushCarriesTheBufferedHistoryThenLaterAppends() throws {
        let feed = Feed()
        try feed.publish("n", 1)
        try feed.publish("n", 2)
        try feed.listen("n")
        feed.batch.replace("n", value: 2, history: feed.store.history("n"))
        try feed.publish("n", 3)
        #expect(feed.take() == [#"{"channel":"n","history":[1,2,3],"value":3}"#])
    }

    @Test func replaceDiscardsWhatWasQueuedButKeepsThePosition() throws {
        let feed = Feed()
        try feed.listen("a")
        try feed.listen("b")
        try feed.publish("a", 1)
        try feed.publish("b", 1)
        feed.batch.replace("a", value: 9, history: [7, 8, 9])
        feed.batch.replace("c", value: 0, history: [])
        #expect(feed.take() == [
            #"{"channel":"a","history":[7,8,9],"value":9}"#,
            #"{"channel":"b","history":[1],"value":1}"#,
            #"{"channel":"c","value":0}"#
        ])
    }

    @Test func aPageThatFallsBehindLosesTheOldestValuesNotTheLatest() throws {
        let feed = Feed()
        feed.limit = 4
        try feed.listen("n")
        for value in 1...10 { try feed.publish("n", value) }
        #expect(feed.take() == [#"{"channel":"n","history":[7,8,9,10],"value":10}"#])
    }

    @Test func removingAChannelDropsOnlyItsEntry() throws {
        let feed = Feed()
        try feed.listen("a")
        try feed.listen("b")
        try feed.publish("a", 1)
        try feed.publish("b", 1)
        feed.batch.remove("a")
        feed.batch.remove("missing")
        #expect(feed.take() == [#"{"channel":"b","history":[1],"value":1}"#])
    }
}
