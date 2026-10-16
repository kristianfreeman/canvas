@testable import CanvasApp
import CanvasCore
import Foundation
import Testing

/// Offscreen snapshots of representative hand-built panels in both themes,
/// drawn with `ImageRenderer` (no window). See `Golden`.
@Suite(.serialized) @MainActor struct NativeGoldenTests {
    static let samples: [String: (title: String, elements: [Element])] = [
        "stats": ("Dashboard", KitSamples.statsCard),
        "table": ("Deploys", KitSamples.tableCard),
        "markdown": ("hello.md", [HelloBlocks.element]),
        "keychips": ("Shortcuts", KitSamples.keyChips),
        "form": ("Approve", KitSamples.form)
    ]

    @Test(arguments: ["stats", "table", "markdown", "keychips", "form"], ["dark", "light"])
    func matchesGolden(name: String, mode: String) throws {
        let sample = try #require(Self.samples[name])
        let built = try tree(sample.elements)
        let image = try #require(Render.image(built, mode: ThemeMode(rawValue: mode) ?? .dark, title: sample.title),
                                 "ImageRenderer gave no image")
        try Golden.check(image, "\(name)-\(mode).png")
    }
}
