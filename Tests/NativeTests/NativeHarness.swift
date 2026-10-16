@testable import CanvasApp
import CanvasCore
import Foundation
import TestSupport

struct NativeTimeout: Error, CustomStringConvertible {
    let description: String
}

/// A `NativeContext` from the built `web/dist/native.js`, with its ops
/// applied to a `ViewTree` and every other message recorded. No window.
@MainActor final class NativeHarness: NativeContextDelegate {
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
    private(set) var batches = 0

    init(runtime: NativeRuntime? = nil) throws {
        context = try (runtime ?? Self.runtime()).makeContext()
        host.delegate = self
        host.didApply = { [weak self] in self?.batches += 1 }
        context.delegate = host
    }

    var tree: ViewTree { host.tree }

    func render(tsx source: String, data: Any? = nil, buttons: [String]? = nil) async -> NativeResult {
        var payload: [String: Any] = ["kind": "tsx", "source": source, "wait": false]
        if let data { payload["data"] = data }
        if let buttons { payload["buttons"] = buttons }
        return await render(payload)
    }

    func render(markdown source: String) async -> NativeResult {
        await render(["kind": "markdown", "source": source, "wait": false])
    }

    func render(_ payload: [String: Any]) async -> NativeResult {
        await withCheckedContinuation { done in context.render(payload) { done.resume(returning: $0) } }
    }

    func setData(_ data: Any) async -> NativeResult {
        await withCheckedContinuation { done in context.setData(data) { done.resume(returning: $0) } }
    }

    func invoke(_ function: Int, _ arguments: [Any] = []) async -> NativeResult {
        await withCheckedContinuation { done in
            context.invoke(function, arguments: arguments) { done.resume(returning: $0) }
        }
    }

    func push(_ batch: [[String: Any]]) async -> NativeResult {
        await withCheckedContinuation { done in context.push(batch) { done.resume(returning: $0) } }
    }

    func reset() async -> NativeResult {
        let result = await withCheckedContinuation { done in context.reset { done.resume(returning: $0) } }
        host.reset()
        return result
    }

    /// Polls until `condition` holds, letting posted messages arrive.
    func waitUntil(_ what: String, timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { throw NativeTimeout(description: "timed out waiting for \(what)") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Every node of `type`, depth first.
    func nodes(_ type: String) -> [ViewNode] {
        Self.descendants(of: tree.root).filter { $0.type == type }
    }

    func node(_ type: String) -> ViewNode? { nodes(type).first }

    /// The `$fn` id of `prop` on the first node of `type`.
    func function(_ type: String, _ prop: String) -> Int? {
        node(type)?.props[prop]?.function
    }

    var errors: [String] {
        messages.compactMap { if case .error(let message, _, _) = $0 { message } else { nil } }
    }

    var results: [Any] {
        messages.compactMap { if case .result(let value) = $0 { value } else { nil } }
    }

    func close() {
        context.tearDown()
    }

    nonisolated func nativeContext(_: NativeContext, didPost message: NativeMessage) {
        MainActor.assumeIsolated { messages.append(message) }
    }

    private static func descendants(of node: ViewNode) -> [ViewNode] {
        node.children.flatMap { [$0] + descendants(of: $0) }
    }
}
