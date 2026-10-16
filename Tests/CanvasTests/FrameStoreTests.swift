import CanvasCore
import CoreGraphics
import Foundation
import Testing

@Suite struct FrameStoreTests {
    private let url = temporaryDirectory().appendingPathComponent("home/frames.json")
    private let screens = [Screens.laptop, Screens.external]
    /// Upper right of the laptop: its middle (1328, 830) is right of and
    /// above the visible frame's middle (756, 472).
    private let hud = CGRect(x: 1168, y: 740, width: 320, height: 180)

    @Test func roundTripsThroughTheFile() {
        FrameStore(url: url).remember(id: "hud", frame: hud, screens: screens)
        let reloaded = FrameStore(url: url).remembered(id: "hud", screens: screens)
        #expect(reloaded == RememberedFrame(frame: hud, anchor: Anchor(.top, .right)))
        #expect(reloaded?.frame == hud)
    }

    @Test func anchorsToTheNearerEdges() {
        let store = FrameStore(url: url)
        store.remember(id: "low", frame: CGRect(x: 24, y: 24, width: 300, height: 200), screens: screens)
        store.remember(id: "left", frame: CGRect(x: -2500, y: 900, width: 300, height: 200), screens: screens)
        #expect(store.remembered(id: "low", screens: screens)?.anchor == Anchor(.bottom, .left))
        #expect(store.remembered(id: "left", screens: screens)?.anchor == Anchor(.top, .left))
    }

    @Test func arrangementIsIndependentOfScreenOrder() {
        FrameStore(url: url).remember(id: "hud", frame: hud, screens: screens)
        let store = FrameStore(url: url)
        #expect(store.remembered(id: "hud", screens: [Screens.external, Screens.laptop])?.frame == hud)
        #expect(store.remembered(id: "hud", screens: [Screens.laptop]) == nil)
        #expect(store.remembered(id: "hud", screens: Screens.all) == nil)
    }

    @Test func arrangementsAreKeptApart() {
        let store = FrameStore(url: url)
        store.remember(id: "hud", frame: hud, screens: screens)
        let docked = CGRect(x: 24, y: 24, width: 320, height: 180)
        store.remember(id: "hud", frame: docked, screens: [Screens.laptop])
        #expect(store.remembered(id: "hud", screens: screens)?.frame == hud)
        #expect(store.remembered(id: "hud", screens: [Screens.laptop])?.frame == docked)
    }

    @Test func corruptOrMissingFilesReadAsEmpty() throws {
        #expect(FrameStore(url: url).remembered(id: "hud", screens: screens) == nil)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for junk in ["{not json", "[]", #"{"version":1,"arrangements":{"a":{"hud":{"x":"no"}}}}"#, ""] {
            try Data(junk.utf8).write(to: url)
            let store = FrameStore(url: url)
            #expect(store.remembered(id: "hud", screens: screens) == nil)
            store.remember(id: "hud", frame: hud, screens: screens)
            #expect(FrameStore(url: url).remembered(id: "hud", screens: screens)?.frame == hud)
        }
    }

    @Test func writesReadableJSON() throws {
        FrameStore(url: url).remember(id: "hud", frame: hud, screens: [Screens.laptop])
        let written = String(bytes: try Data(contentsOf: url), encoding: .utf8)
        #expect(written == """
            {"arrangements":{"0,0,1512,982":{"hud":{"anchor":{"horizontal":"right","vertical":"top"},\
            "height":180,"width":320,"x":1168,"y":740}}},"version":1}
            """)
    }

    @Test func framesOffEveryScreenAreNotSaved() {
        let store = FrameStore(url: url)
        store.remember(id: "lost", frame: CGRect(x: 9000, y: 9000, width: 300, height: 200), screens: screens)
        #expect(store.remembered(id: "lost", screens: screens) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func forgetClearsEveryArrangementOfThatIdOnly() {
        let store = FrameStore(url: url)
        store.remember(id: "hud", frame: hud, screens: screens)
        store.remember(id: "hud", frame: hud, screens: [Screens.laptop])
        store.remember(id: "other", frame: hud, screens: screens)
        store.forget(id: "hud")
        let reloaded = FrameStore(url: url)
        #expect(reloaded.remembered(id: "hud", screens: screens) == nil)
        #expect(reloaded.remembered(id: "hud", screens: [Screens.laptop]) == nil)
        #expect(reloaded.remembered(id: "other", screens: screens)?.frame == hud)
    }

    @Test(arguments: [
        ("{}", true), (#"{"width":500,"screen":"main"}"#, true), (#"{"position":"center"}"#, false),
        (#"{"at":{"x":10,"y":10}}"#, false), (#"{"stack":"notes"}"#, false)
    ])
    func restoresOnlyWithoutPositionOrAt(request: String, restores: Bool) throws {
        let store = FrameStore(url: url)
        store.remember(id: "hud", frame: hud, screens: screens)
        let restored = store.restore(id: "hud", placement: try placement(request), screens: screens)
        #expect(restored?.frame == (restores ? hud : nil))
        #expect(store.remembered(id: "hud", screens: screens) != nil)
    }

    @Test func forgetFlagClearsAndRestoresNothing() throws {
        let store = FrameStore(url: url)
        store.remember(id: "hud", frame: hud, screens: screens)
        #expect(store.restore(id: "hud", placement: try placement(#"{"forget":true}"#), screens: screens) == nil)
        #expect(store.restore(id: "hud", placement: try placement("{}"), screens: screens) == nil)
        #expect(FrameStore(url: url).remembered(id: "hud", screens: screens) == nil)
    }
}
