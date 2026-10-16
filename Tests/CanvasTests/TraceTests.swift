import CanvasCore
import Foundation
import Testing

@Suite struct TraceTests {
    @Test func firstMarkWins() {
        let record = TraceRecord(id: "a", command: "show", requested: true)
        record.mark(.dispatch, at: 100)
        record.mark(.dispatch, at: 200)
        record.mark(.reply, at: 300)
        #expect(record.stages == ["dispatch": 100, "reply": 300])
        #expect(canonical(record.json) == #"{"cmd":"show","id":"a","stages":{"dispatch":100,"reply":300}}"#)
    }

    @Test func logKeepsTheNewestRecords() {
        let log = TraceLog()
        let capacity = TraceLog.defaultCapacity
        for index in 0..<capacity + 36 {
            log.append(TraceRecord(id: "p\(index)", command: "show", requested: false))
        }
        let ids = log.json.compactMap { $0["id"] as? String }
        #expect(ids == (36..<capacity + 36).map { "p\($0)" })
    }

    @Test func noteAppearsOnlyWhenSet() {
        let record = TraceRecord(id: "a", command: "show", requested: false)
        #expect(record.json["note"] == nil)
        record.note = "new"
        #expect(record.json["note"] as? String == "new")
    }

    @Test func theRouteJoinsTheNoteAndTheLatestWins() {
        let record = TraceRecord(id: "a", command: "show", requested: false)
        record.route = "native"
        #expect(record.json["note"] as? String == "route=native")
        record.note = "fresh"
        record.route = "fallback"
        #expect(record.json["note"] as? String == "fresh route=fallback")
    }

    @Test func summaryIsMillisecondsSinceCLIStart() {
        let start: UInt64 = 5_000_000_000
        let line = TraceSummary.line(
            cliStart: start,
            stages: ["accept": start + 410_000, "reply": start + 12_345_678, "sent": start + 1_000_000],
            end: start + 13_000_000)
        #expect(line["total_ms"] as? Double == 13)
        #expect(line["stages"] as? [String: Double] == ["accept": 0.41, "cliStart": 0, "reply": 12.346, "sent": 1])
    }

    @Test func summaryTextIsShortTimeOrderedJSON() {
        let start: UInt64 = 1_000_000_000
        let line = TraceSummary.line(
            cliStart: start,
            stages: ["reply": start + 12_345_678, "accept": start + 531_000, "sent": start + 717_000],
            end: start + 13_000_000)
        let text = TraceSummary.text(line)
        #expect(text == #"{"total_ms":13.0,"stages":{"cliStart":0.0,"accept":0.531,"sent":0.717,"reply":12.346}}"#)
        #expect(canonical(json(text)) == canonical(line))
    }

    @Test func summaryHandlesStagesBeforeStart() {
        let line = TraceSummary.line(cliStart: 2_000_000, stages: ["accept": 1_000_000], end: 2_000_000)
        #expect(line["stages"] as? [String: Double] == ["accept": -1, "cliStart": 0])
    }

    @Test func stagesComeFromTheEventTraceObject() {
        let event = json(#"{"event":"rendered","trace":{"accept":12,"parsed":15,"bogus":"x"}}"#)
        #expect(TraceSummary.stages(in: event as? [String: Any] ?? [:]) == ["accept": 12, "parsed": 15])
        #expect(TraceSummary.stages(in: ["event": "rendered"]).isEmpty)
    }

    @Test func clockTracksTheMonotonicClock() {
        let clockStart = Clock.now()
        let monoStart = clock_gettime_nsec_np(CLOCK_MONOTONIC)
        Thread.sleep(forTimeInterval: 0.05)
        let clockElapsed = Double(Clock.now() - clockStart)
        let monoElapsed = Double(clock_gettime_nsec_np(CLOCK_MONOTONIC) - monoStart)
        #expect(clockElapsed >= 45_000_000)
        #expect(abs(clockElapsed - monoElapsed) < 2_000_000)
        #expect(Clock.milliseconds(from: 1_000_000, to: 3_500_000) == 2.5)
    }
}

@Suite struct PathsTests {
    @Test func canvasHomeOverridesTheSupportDirectory() {
        #expect(Paths.home(environment: ["CANVAS_HOME": "/tmp/canvas-x"]).path == "/tmp/canvas-x")
    }

    @Test func defaultHomeIsApplicationSupport() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Canvas").path
        #expect(Paths.home(environment: [:]).path == expected)
        #expect(Paths.home(environment: ["CANVAS_HOME": ""]).path == expected)
    }
}
