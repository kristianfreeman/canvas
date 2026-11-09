import AppKit
@testable import CanvasApp
import Foundation
import Testing
import TestSupport

/// `<img>` with a `file://` URL outside the renderer's own folder, as agents
/// write them: a path with spaces, percent-encoded, and a cache-busting
/// query string.
@MainActor @Suite(.serialized) struct LocalImageBridgeTests {
    private let page = BridgePage()

    static let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="40" height="20" fill="red"/></svg>
        """

    @Test(arguments: ["", "?r=0"])
    func aFileImageOutsideTheRendererLoads(query: String) async throws {
        defer { page.close() }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("canvas images \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("plasma light.svg")
        try Self.svg.write(to: file, atomically: true, encoding: .utf8)
        #expect(file.absoluteString.contains("%20"))

        let source = """
            export default function App({ data }: { data: { src: string } }) {
              return <img id="probe" src={data.src} style={{ width: '100%' }} />
            }
            """
        let src = file.absoluteString + query
        let result = try await page.show(["source": source, "kind": "tsx", "data": ["src": src]])
        #expect(result.error == nil)
        try await page.waitFor("document.getElementById('probe')?.complete")
        let size = try await page.evaluate("const img = document.getElementById('probe'); return img.naturalWidth")
        #expect(size as? Int == 40, "naturalWidth \(size) for \(file.absoluteString + query)")
    }
}
