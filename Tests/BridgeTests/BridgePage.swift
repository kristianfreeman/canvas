import AppKit
@testable import CanvasApp
import CanvasCore
import Foundation
import TestSupport

struct BridgeTimeout: Error, CustomStringConvertible {
    let description: String
}

/// The built renderer in a `WebPage` that is never put in a window, driven
/// through the calls the server makes: `render` with a wire request's
/// payload, `setData`, `canvas.push` through the channel hub, and
/// `canvas.setAccent`. Without a window WebKit runs scripts, layout and the
/// ResizeObserver, but not animation frames, so `painted` never arrives.
final class BridgePage: PanelContentDelegate {
    let page: WebPage
    private(set) var paints = 0
    private(set) var resizes: [CGFloat] = []
    private(set) var errors: [String] = []
    private(set) var submitted: [Any] = []
    private(set) var published: [(channel: String, value: Any)] = []
    /// Off for snapshots: `canvas.sys.*` would draw this Mac's live numbers.
    var liveChannels = true

    @MainActor init(width: CGFloat = 720) {
        page = WebPage(indexURL: Repo.indexURL)
        page.view.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        page.delegate = self
        page.load()
    }

    /// Renders what the server would render for this `show` request.
    @MainActor func show(_ request: [String: Any]) async throws -> RenderResult {
        var json = request
        if json["source"] == nil { json["source"] = "" }
        let payload = try ShowRequest(json).payload
        return await withCheckedContinuation { done in
            page.render(payload) { done.resume(returning: $0) }
        }
    }

    @MainActor func setData(_ data: Any) async -> CGFloat? {
        await withCheckedContinuation { done in
            page.setData(data) { done.resume(returning: $0) }
        }
    }

    /// Runs `body` as an async function in the page and returns its value.
    @MainActor func evaluate(_ body: String) async throws -> Any {
        try await withCheckedThrowingContinuation { done in
            page.call(body) { done.resume(with: $0) }
        }
    }

    @MainActor func text(_ selector: String) async throws -> String {
        let value = try await evaluate("return document.querySelector(\(quoted(selector)))?.textContent ?? '<missing>'")
        return value as? String ?? "<not a string>"
    }

    /// Polls `condition` (a JavaScript expression) until it is truthy.
    @MainActor func waitFor(_ condition: String, timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try await evaluate("return Boolean(\(condition))") as? Bool == true { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw BridgeTimeout(description: "timed out waiting for \(condition)")
    }

    @MainActor func close() {
        page.tearDown()
    }

    private func quoted(_ text: String) -> String {
        JSON.string(text) ?? "''"
    }

    // MARK: PanelContentDelegate, routed as PanelController routes it

    func contentDidPaint() { paints += 1 }
    func contentDidReportError(_ message: String) { errors.append(message) }
    func contentDidResize(height: CGFloat) { resizes.append(height) }
    func contentDidSubmit(_ value: Any) { submitted.append(value) }
    func contentDidRequestClose() {}

    func contentDidSubscribe(channel: String, every: Int?) {
        guard liveChannels else { return }
        ChannelHub.shared.subscribe(page, channel: channel, every: every)
    }

    func contentDidUnsubscribe(channel: String) {
        ChannelHub.shared.unsubscribe(page, channel: channel)
    }

    func contentDidPublish(channel: String, value: Any) {
        published.append((channel, value))
        try? ChannelHub.shared.publish(ChannelMessage(channel: channel, value: value))
    }
}
