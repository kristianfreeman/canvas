import AppKit
@testable import CanvasApp
import CanvasCore
import Foundation
import SwiftUI
import Testing
import TestSupport

/// Real mouse events on a Markdown task box. Accessibility presses skip hit
/// testing, so only a click shows whether the hollow open box can be hit in
/// its middle.
@Suite(.serialized) @MainActor struct NativeTaskClickTests {
    static func markdown(checked: Bool) throws -> ViewTree {
        let item: [String: Any] = ["task": true, "checked": checked, "line": 2,
                                   "blocks": [HelloBlocks.para([HelloBlocks.run("Ship it")])]]
        return try tree(node("Markdown", ["blocks": [["t": "list", "ordered": false, "items": [item]]],
                                          "onToggle": ["$fn": 7]]))
    }

    @Test(arguments: [false, true])
    func clickingTheMiddleOfTheBoxToggles(checked: Bool) throws {
        let events = RecordingEvents()
        let panel = ClickablePanel(try Self.markdown(checked: checked), events: events)
        let box = try panel.box()
        panel.click(at: CGPoint(x: box.midX, y: box.midY))
        panel.close()
        #expect(events.invoked.count == 1, "box \(box), checked \(checked)")
        let call = try #require(events.invoked.first)
        #expect(call.fn == 7)
        #expect(canonical(call.args) == canonical([["line": 2, "checked": !checked]]))
    }
}

/// A native panel in a borderless window. SwiftUI only acts on clicks in a
/// window that is ordered in, so it is, but fully transparent, behind other
/// windows and far off every screen, so nothing shows.
@MainActor
final class ClickablePanel {
    let window: NSWindow
    let view: NSHostingView<NativePanelView>
    private let surface: NativeSurface

    init(_ tree: ViewTree, events: NativeEvents) {
        surface = NativeSurface(root: tree.root)
        surface.events = events
        view = NSHostingView(rootView: NativePanelView(surface: surface, controls: .still))
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: Render.width, height: 300),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.alphaValue = 0
        window.setFrameOrigin(CGPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        settle()
    }

    func close() { window.orderOut(nil) }

    func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        view.layoutSubtreeIfNeeded()
    }

    /// The task box, in view points from the top left: the bounds of the
    /// ink left of the item text, below the header.
    func box() throws -> CGRect {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let pixels = try #require(rep.cgImage.flatMap(Pixels.init))
        let scale = CGFloat(pixels.width) / view.bounds.width
        let background = pixels.pixel(pixels.width - 2, pixels.height - 2)
        var ink: CGRect?
        for y in Int(PanelHeader.height * scale)..<pixels.height {
            for x in 0..<Int(44 * scale) where zip(pixels.pixel(x, y), background).contains(where: {
                abs($0 - $1) > 40
            }) {
                let point = CGRect(x: CGFloat(x) / scale, y: CGFloat(y) / scale, width: 1 / scale, height: 1 / scale)
                ink = ink.map { $0.union(point) } ?? point
            }
        }
        return try #require(ink)
    }

    /// A left click at `point`, in view points from the top left.
    func click(at point: CGPoint) {
        let flipped = view.isFlipped ? point : CGPoint(x: point.x, y: view.bounds.height - point.y)
        let location = view.convert(flipped, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            else { continue }
            window.sendEvent(event)
            settle()
        }
    }
}
