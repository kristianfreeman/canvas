@testable import CanvasApp
import CanvasCore
import Foundation
import TestSupport

/// A real `NativeContext` from the built web/dist/native.js with its ops
/// applied to a `ViewTree`, as a panel would run an example. No window.
@MainActor final class ExamplePage: NativeContextDelegate {
    private static var shared: NativeRuntime?

    static func runtime() throws -> NativeRuntime {
        if let shared { return shared }
        let runtime = try NativeRuntime(webDir: Repo.webDir)
        shared = runtime
        return runtime
    }

    let context: NativeContext
    let host = NativeContextTree()
    private(set) var messages: [NativeMessage] = []

    init() throws {
        context = try Self.runtime().makeContext()
        host.delegate = self
        context.delegate = host
    }

    var tree: ViewTree { host.tree }

    var errors: [String] {
        messages.compactMap { if case .error(let message, _, _) = $0 { message } else { nil } }
    }

    func render(_ payload: [String: Any]) async -> NativeResult {
        await withCheckedContinuation { done in context.render(payload) { done.resume(returning: $0) } }
    }

    func push(_ batch: [[String: Any]]) async -> NativeResult {
        await withCheckedContinuation { done in context.push(batch) { done.resume(returning: $0) } }
    }

    func invoke(_ function: Int) async -> NativeResult {
        await withCheckedContinuation { done in context.invoke(function, arguments: []) { done.resume(returning: $0) } }
    }

    func close() { context.tearDown() }

    nonisolated func nativeContext(_: NativeContext, didPost message: NativeMessage) {
        MainActor.assumeIsolated { messages.append(message) }
    }
}

/// What each example is shown with: its data and the channel pushes that
/// follow, so no panel is a bare placeholder.
enum ExampleCases {
    struct Case {
        let file: String
        var data: Any?
        var pushes: [[String: Any]] = []
    }

    static let names = ["approve", "dashboard", "deploy", "keys", "keys-empty", "live", "top", "top-waiting", "hello"]

    static func source(_ file: String) throws -> String {
        try String(contentsOf: Repo.examples.appendingPathComponent(file), encoding: .utf8)
    }

    static func payload(_ name: String) throws -> (payload: [String: Any], pushes: [[String: Any]]) {
        let item = try make(name)
        let kind = item.file.hasSuffix(".md") ? "markdown" : "tsx"
        var payload: [String: Any] = ["kind": kind, "source": try source(item.file), "title": item.file, "wait": true]
        if let data = item.data { payload["data"] = data }
        return (payload, item.pushes)
    }

    private static func make(_ name: String) throws -> Case {
        try cases[name]?() ?? Case(file: "\(name).tsx")
    }

    private static let cases: [String: () throws -> Case] = [
        "approve": { Case(file: "approve.tsx", data: plan) },
        "keys": { Case(file: "keys.tsx", data: try keysData()) },
        "keys-empty": { Case(file: "keys.tsx") },
        "live": { Case(file: "live.tsx", data: ["channel": "demo.load", "label": "Load", "unit": "%"], pushes: [
            ["channel": "demo.load", "value": 42, "history": [18, 25, 21, 34, 30, 47, 39, 55, 49, 42]]
        ]) },
        "top": { Case(file: "top.tsx", pushes: SysSample.batch) },
        "top-waiting": { Case(file: "top.tsx") },
        "hello": { Case(file: "hello.md") }
    ]

    static let plan: [String: Any] = [
        "title": "Deploy api-gateway to production", "from": "v2.13.2", "to": "v2.14.0",
        "changes": ["Rate limiter moves to Redis-backed buckets", "New /v2/batch endpoint behind a flag",
                    "Migration 0042 adds an index on requests(created_at)"]
    ]

    static func keysData() throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: Repo.examples.appendingPathComponent("keys.json")))
    }
}

/// One push of every canvas.sys.* channel top.tsx reads, shaped as in
/// docs/protocol.md, with a few seconds of history for the sparklines.
enum SysSample {
    static let gib = 1_073_741_824.0

    static func cpu(_ total: Double) -> [String: Any] {
        ["total": total, "cores": [0.92, 0.18, 0.71, 0.33, 0.12, 0.55, 0.08, 0.4].map { min(1, $0 * total * 2) }]
    }

    static var batch: [[String: Any]] {
        let totals = [0.22, 0.31, 0.27, 0.44, 0.38, 0.52, 0.41, 0.36]
        let memory = (0..<6).map { step in
            ["total": 16 * gib, "used": (8.5 + Double(step) * 0.2) * gib, "app": 6 * gib, "wired": 2 * gib,
             "compressed": gib, "swapUsed": 0.0] as [String: Any]
        }
        let net = [2048.0, 9000, 5200, 14_000, 7600, 3100].map { rx in
            ["rx": rx, "tx": rx / 3, "rxTotal": 3 * gib, "txTotal": gib / 2] as [String: Any]
        }
        return [
            ["channel": "canvas.sys.cpu", "value": cpu(0.36), "history": totals.map(cpu)],
            ["channel": "canvas.sys.memory", "value": memory[5], "history": memory],
            ["channel": "canvas.sys.net", "value": net[5], "history": net],
            ["channel": "canvas.sys.disk", "value": ["read": 0, "write": 4096, "used": 200 * gib, "total": 500 * gib]],
            ["channel": "canvas.sys.battery", "value": ["percent": 82, "charging": false, "source": "battery"]],
            ["channel": "canvas.sys.thermal", "value": ["state": "nominal"]],
            ["channel": "canvas.sys.procs", "value": procs]
        ]
    }

    static let procs: [[String: Any]] = [
        ["pid": 812, "name": "WindowServer", "cpu": 0.412, "mem": 1.1 * gib],
        ["pid": 4021, "name": "Cursor Helper (Renderer)", "cpu": 0.286, "mem": 2.3 * gib],
        ["pid": 1977, "name": "Ghostty", "cpu": 0.094, "mem": 0.42 * gib],
        ["pid": 655, "name": "kernel_task", "cpu": 0.071, "mem": 0.08 * gib],
        ["pid": 3310, "name": "Slack Helper", "cpu": 0.033, "mem": 0.61 * gib],
        ["pid": 1, "name": "launchd", "cpu": 0.004, "mem": 0.016 * gib]
    ]
}
