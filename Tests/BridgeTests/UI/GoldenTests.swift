@testable import CanvasApp
import Foundation
import Testing
import TestSupport

/// One example file in one theme, and its golden in `Tests/golden/`.
struct Example: Sendable, CustomTestStringConvertible {
    let file: String
    let theme: String

    var testDescription: String { "\(file) (\(theme))" }

    static var all: [Self] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Repo.examples.path)) ?? []
        return files.filter { $0.hasSuffix(".md") || $0.hasSuffix(".tsx") }.sorted().flatMap { file in
            ["dark", "light"].map { Self(file: file, theme: $0) }
        }
    }

    private var stem: String { (file as NSString).deletingPathExtension }

    var golden: URL { Repo.root.appendingPathComponent("Tests/golden/\(stem)-\(theme).png") }
    var failure: URL { Repo.root.appendingPathComponent(".build/golden-failures/\(stem)-\(theme).png") }

    /// A fixed accent, so the system's accent color can't change the image.
    func request() throws -> [String: Any] {
        let url = Repo.examples.appendingPathComponent(file)
        var request: [String: Any] = [
            "source": try String(contentsOf: url, encoding: .utf8), "title": file, "theme": theme,
            "kind": file.hasSuffix(".tsx") ? "tsx" : "markdown", "accent": "#0a84ff"
        ]
        let data = Repo.examples.appendingPathComponent("\(stem).json")
        if let json = try? Data(contentsOf: data), let value = try? JSONSerialization.jsonObject(with: json) {
            request["data"] = value
        }
        return request
    }
}

/// Snapshots of every example against `Tests/golden/`. `UPDATE_GOLDENS=1`
/// rewrites the goldens instead of comparing. A mismatch leaves the actual
/// image in `.build/golden-failures/`.
@MainActor @Suite(.serialized, .onScreen) struct UIGoldenTests {
    /// Text antialiasing differs slightly between runs; 3×3 block averages
    /// absorb it.
    private static let blockSize = 3
    private static let channelTolerance = 8
    private static let allowedFraction = 0.001

    @Test(arguments: Example.all)
    func matchesItsGolden(_ example: Example) async throws {
        let host = OnScreenPage()
        defer { host.close() }
        host.bridge.liveChannels = false
        let result = try await host.bridge.show(try example.request())
        #expect(result.error == nil, "\(result.error ?? "")")
        host.resize(height: min(result.height ?? 400, 1600))
        try await host.painted(after: 0)
        try await host.bridge.waitFor("document.fonts.status === 'loaded'")
        try await Task.sleep(nanoseconds: 500_000_000)
        let actual = try #require(Bitmap(try await host.snapshot()))
        if ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1" {
            try actual.writePNG(to: example.golden)
            return
        }
        let golden = try #require(
            Bitmap(contentsOf: example.golden),
            "no golden at \(example.golden.path); make it with UPDATE_GOLDENS=1 scripts/test.sh --ui")
        let (differing, total) = actual.differingBlocks(
            from: golden, size: Self.blockSize, tolerance: Self.channelTolerance)
        let allowed = Int(Double(total) * Self.allowedFraction)
        if differing > allowed { try actual.writePNG(to: example.failure) }
        let sizes = "\(actual.width)x\(actual.height), golden \(golden.width)x\(golden.height)"
        #expect(
            differing <= allowed,
            "\(differing) blocks differ (\(allowed) allowed) at \(sizes); actual image in \(example.failure.path)")
    }
}
