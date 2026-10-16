import Foundation
import Testing

@MainActor @Suite(.serialized, .onScreen) struct UIPaintTests {
    @Test func everyRenderIsFollowedByPainted() async throws {
        let host = OnScreenPage()
        defer { host.close() }
        _ = try await host.bridge.show(["source": "# First"])
        try await host.painted(after: 0)
        let painted = host.bridge.paints
        _ = try await host.bridge.show(["source": "export default () => <p>Second</p>", "kind": "tsx"])
        try await host.painted(after: painted)
    }
}
