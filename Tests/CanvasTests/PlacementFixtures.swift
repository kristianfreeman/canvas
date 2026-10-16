import CanvasCore
import CoreGraphics
import Foundation

/// The displays the positioning tests run on, in AppKit global coordinates.
enum Screens {
    /// 14" MacBook Pro: 1512x982 points, a 38 pt menu bar under the notch.
    static let laptop = ScreenInfo(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
        name: "Built-in Retina Display", index: 1, isMain: true)

    /// 2560x1440 to the left of the laptop, bottoms aligned, 25 pt menu bar.
    static let external = ScreenInfo(
        frame: CGRect(x: -2560, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: -2560, y: 0, width: 2560, height: 1415),
        name: "DELL U2723QE", index: 2)

    /// 1080x1920 portrait above the laptop, 25 pt menu bar.
    static let portrait = ScreenInfo(
        frame: CGRect(x: 200, y: 982, width: 1080, height: 1920),
        visibleFrame: CGRect(x: 200, y: 982, width: 1080, height: 1895),
        name: "LG UltraFine", index: 3)

    static let all = [laptop, external, portrait]
}

/// A placement from wire JSON text, as the CLI would send it.
func placement(_ text: String) throws -> Placement {
    guard let fields = json(text) as? [String: Any] else { fatalError("not a JSON object: \(text)") }
    return try Placement(json: fields)
}

func contains(_ outer: CGRect, _ inner: CGRect) -> Bool {
    inner.minX >= outer.minX && inner.maxX <= outer.maxX && inner.minY >= outer.minY && inner.maxY <= outer.maxY
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
