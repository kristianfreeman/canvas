import Foundation

public enum TraceStage: String, CaseIterable {
    case cliStart, accept, parsed, dispatch, jsStart, jsEnd, visible, painted, reply, sent, received
}

/// The server's stage timestamps (`Clock` nanoseconds) for one request.
public final class TraceRecord {
    public let id: String
    public let command: String
    /// Whether the request asked for the stages in its reply.
    public let requested: Bool
    /// How the server handled it, for example `new` or `replace` for a show.
    public var note: String?
    /// Which renderer drew a show: `native`, `web`, or `fallback` when the
    /// native attempt needed WebKit. The latest wins.
    public var route: String?
    public private(set) var stages: [String: UInt64] = [:]

    public init(id: String, command: String, requested: Bool) {
        self.id = id
        self.command = command
        self.requested = requested
    }

    /// The first mark of a stage wins, so re-renders don't move it.
    public func mark(_ stage: TraceStage, at time: UInt64 = Clock.now()) {
        if stages[stage.rawValue] == nil { stages[stage.rawValue] = time }
    }

    public var json: [String: Any] {
        var json: [String: Any] = ["id": id, "cmd": command, "stages": stages]
        let notes = [note, route.map { "route=\($0)" }].compactMap { $0 }
        if !notes.isEmpty { json["note"] = notes.joined(separator: " ") }
        return json
    }
}

/// The most recent trace records, oldest first.
public final class TraceLog {
    public static let defaultCapacity = 256
    private var records: History<TraceRecord>

    public init(capacity: Int = defaultCapacity) {
        records = History(capacity: capacity)
    }

    public func append(_ record: TraceRecord) {
        records.append(record)
    }

    public var json: [[String: Any]] {
        records.elements.map(\.json)
    }
}

public enum TraceSummary {
    /// The CLI's `--trace` line: each stage in milliseconds since `cliStart`,
    /// and the total up to `end`.
    public static func line(cliStart: UInt64, stages: [String: UInt64], end: UInt64) -> [String: Any] {
        var relative = stages.mapValues { round(Clock.milliseconds(from: cliStart, to: $0)) }
        relative[TraceStage.cliStart.rawValue] = 0
        return ["total_ms": round(Clock.milliseconds(from: cliStart, to: end)), "stages": relative]
    }

    /// `line` as JSON text, stages in time order and numbers in their
    /// shortest form.
    public static func text(_ line: [String: Any]) -> String {
        let stages = (line["stages"] as? [String: Double] ?? [:])
            .sorted { ($0.value, $0.key) < ($1.value, $1.key) }
            .map { "\(JSON.string($0.key) ?? "\"\""):\($0.value)" }
            .joined(separator: ",")
        return "{\"total_ms\":\(line["total_ms"] as? Double ?? 0),\"stages\":{\(stages)}}"
    }

    /// Server stages from a `rendered` or `error` event's `trace` object.
    public static func stages(in event: [String: Any]) -> [String: UInt64] {
        guard let trace = event["trace"] as? [String: Any] else { return [:] }
        return trace.compactMapValues { ($0 as? NSNumber)?.uint64Value }
    }

    private static func round(_ ms: Double) -> Double {
        (ms * 1000).rounded() / 1000
    }
}
