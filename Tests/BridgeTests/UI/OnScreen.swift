import AppKit
@testable import CanvasApp
import Foundation
import Testing
import WebKit

extension Trait where Self == ConditionTrait {
    /// Tests that put windows on screen run only under `scripts/test.sh --ui`.
    static var onScreen: Self {
        .enabled(
            if: ProcessInfo.processInfo.environment["CANVAS_UI_TESTS"] == "1",
            "puts windows on screen; run scripts/test.sh --ui")
    }
}

/// A `BridgePage` in a borderless window ordered in at the top left of the
/// main screen, so WebKit runs animation frames (`painted`) and can take
/// snapshots.
@MainActor final class OnScreenPage {
    let bridge: BridgePage
    private let window: NSWindow

    init(width: CGFloat = 720, height: CGFloat = 400) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        bridge = BridgePage(width: width)
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = NSWindow(
            contentRect: NSRect(x: visible.minX, y: visible.maxY - height, width: width, height: height),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = bridge.page.view
        Self.ignoreOcclusion(bridge.page.webView)
        window.orderFrontRegardless()
    }

    /// The test process never runs an app event loop, so the window's
    /// occlusion state never turns visible and WebKit withholds animation
    /// frames. This SPI makes the web view ignore occlusion.
    private static func ignoreOcclusion(_ webView: WKWebView) {
        let selector = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        guard webView.responds(to: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(webView.method(for: selector), to: Setter.self)(webView, selector, false)
    }

    /// Keeps the top edge where it is.
    func resize(height: CGFloat) {
        var frame = window.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        window.setFrame(frame, display: true)
    }

    /// Waits for the `painted` that follows the latest render.
    func painted(after count: Int, timeout: TimeInterval = 3) async throws {
        try await waitUntil("the page paints", timeout: timeout) { bridge.paints > count }
    }

    func snapshot() async throws -> CGImage {
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        let image = try await bridge.page.webView.takeSnapshot(configuration: config)
        var rect = NSRect(origin: .zero, size: image.size)
        return try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
    }

    func close() {
        window.orderOut(nil)
        window.contentView = nil
        bridge.close()
    }
}
