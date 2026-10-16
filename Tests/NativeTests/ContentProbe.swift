import AppKit
@testable import CanvasApp
import CanvasCore
import Foundation
import TestSupport

/// A `NativePanelContent` driven the way a panel drives it, offscreen: no
/// window, its hosting view sized to a panel's width. Records what the
/// content reports and routes channel hooks through the real hub, as
/// `PanelController` does.
@MainActor final class ContentProbe: PanelContentDelegate {
    let content: NativePanelContent
    private(set) var resizes: [CGFloat] = []
    private(set) var errors: [String] = []
    private(set) var submitted: [Any] = []
    private(set) var closes: [String] = []
    private(set) var needsWeb = 0

    init(runtime: NativeRuntime? = nil, width: CGFloat = 560) throws {
        let runtime = try runtime ?? NativeHarness.runtime()
        content = NativePanelContent(contexts: { runtime.makeContext() }, size: NSSize(width: width, height: 400))
        content.delegate = self
    }

    func render(tsx source: String, data: Any? = nil, buttons: [String]? = nil) async -> RenderResult {
        var payload: [String: Any] = ["kind": "tsx", "source": source, "wait": false]
        if let data { payload["data"] = data }
        if let buttons { payload["buttons"] = buttons }
        return await render(payload)
    }

    func render(markdown source: String, buttons: [String]? = nil) async -> RenderResult {
        var payload: [String: Any] = ["kind": "markdown", "source": source, "wait": false]
        if let buttons { payload["buttons"] = buttons }
        return await render(payload)
    }

    func render(_ payload: [String: Any]) async -> RenderResult {
        await withCheckedContinuation { done in content.render(payload) { done.resume(returning: $0) } }
    }

    func setData(_ data: Any) async -> CGFloat? {
        await withCheckedContinuation { done in content.setData(data) { done.resume(returning: $0) } }
    }

    func nodes(_ type: String) -> [ViewNode] {
        content.tree.root.subtree.filter { $0.type == type }
    }

    /// The `$fn` id of `onClick` on the button labelled `label`.
    func click(_ label: String) throws -> Int {
        guard let button = nodes("Button").first(where: { $0.textContent == label }),
              let function = button.props["onClick"]?.function else {
            throw NativeTimeout(description: "no button \(label)")
        }
        return function
    }

    var text: String {
        nodes("Text").map(\.textContent).joined(separator: "|")
    }

    func close() {
        content.tearDown()
    }

    func waitUntil(_ what: String, timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { throw NativeTimeout(description: "timed out waiting for \(what)") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: PanelContentDelegate

    nonisolated func contentDidReportError(_ message: String) {
        MainActor.assumeIsolated { errors.append(message) }
    }

    nonisolated func contentDidResize(height: CGFloat) {
        MainActor.assumeIsolated { resizes.append(height) }
    }

    nonisolated func contentDidSubmit(_ value: Any) {
        MainActor.assumeIsolated { submitted.append(value) }
    }

    nonisolated func contentDidRequestClose() {
        MainActor.assumeIsolated { closes.append("close") }
    }

    nonisolated func contentDidRequestEscapeClose() {
        MainActor.assumeIsolated { closes.append("escape") }
    }

    nonisolated func contentNeedsWeb() {
        MainActor.assumeIsolated { needsWeb += 1 }
    }

    nonisolated func contentDidSubscribe(channel: String, every: Int?) {
        MainActor.assumeIsolated { ChannelHub.shared.subscribe(content, channel: channel, every: every) }
    }

    nonisolated func contentDidUnsubscribe(channel: String) {
        MainActor.assumeIsolated { ChannelHub.shared.unsubscribe(content, channel: channel) }
    }

    nonisolated func contentDidPublish(channel: String, value: Any) {
        MainActor.assumeIsolated { _ = try? ChannelHub.shared.publish(ChannelMessage(channel: channel, value: value)) }
    }
}
