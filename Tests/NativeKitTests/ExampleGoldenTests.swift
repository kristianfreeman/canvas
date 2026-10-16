@testable import CanvasApp
import CanvasCore
import Foundation
import SwiftUI
import Testing

/// Every example through the real runtime into a view tree, then drawn
/// offscreen at the default panel width in both themes. Goldens live in
/// Tests/golden/native/examples.
@Suite(.serialized) @MainActor struct ExampleGoldenTests {
    static let width: CGFloat = 720

    static func rendered(_ name: String) async throws -> ExamplePage {
        let page = try ExamplePage()
        let (payload, pushes) = try ExampleCases.payload(name)
        let result = await page.render(payload)
        #expect(result.error == nil && !result.needsWeb, "\(name): \(result.error ?? "needs WebKit")")
        if !pushes.isEmpty {
            let pushed = await page.push(pushes)
            #expect(pushed.error == nil, "\(name): \(pushed.error ?? "")")
        }
        #expect(page.errors.isEmpty, "\(name): \(page.errors)")
        #expect(!page.tree.root.children.isEmpty, "\(name) rendered nothing")
        return page
    }

    @Test(arguments: ExampleCases.names, ["dark", "light"])
    func example(name: String, mode: String) async throws {
        let page = try await Self.rendered(name)
        defer { page.close() }
        let file = try #require(try ExampleCases.payload(name).payload["title"] as? String)
        let theme = Theme(mode: ThemeMode(rawValue: mode) ?? .dark)
        let surface = NativeSurface(root: page.tree.root, title: file, theme: theme)
        let image = try #require(Render.image(surface, width: Self.width), "ImageRenderer gave no image")
        try Golden.check(image, "examples/\(name)-\(mode).png")
    }
}
