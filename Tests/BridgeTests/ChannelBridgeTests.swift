@testable import CanvasApp
import CanvasCore
import Foundation
import Testing
import TestSupport

/// Channels end to end inside one process: page hooks subscribe through the
/// hub, publishes arrive by `canvas.push`, and page publishes come back.
@MainActor @Suite(.serialized) struct ChannelBridgeTests {
    private let page = BridgePage()
    /// The hub is process-wide, so every run uses fresh channel names.
    private let prefix = "bridge.r\(UInt32.random(in: 0...UInt32.max))"

    private func subscribed(_ channel: String) async throws {
        try await waitUntil("the page subscribes to \(channel)") {
            ChannelHub.shared.store.subscriberCount(channel) == 1
        }
    }

    @Test func aPublishedValueReachesUseChannelAndMergesApply() async throws {
        let channel = "\(prefix).status"
        let source = """
            import { useChannel } from 'canvas'
            export default function App() {
              const value = useChannel('\(channel)')
              if (value === undefined) return <p id="value">none</p>
              return <p id="value">{`${value.step}:${'n' in value ? value.n : 'deleted'}`}</p>
            }
            """
        _ = try await page.show(["source": source, "kind": "tsx"])
        defer { page.close() }
        #expect(try await page.text("#value") == "none")
        try await subscribed(channel)
        try ChannelHub.shared.publish(ChannelMessage(channel: channel, value: ["step": "build", "n": 1]))
        try await page.waitFor("document.getElementById('value').textContent === 'build:1'")
        try ChannelHub.shared.publish(ChannelMessage(channel: channel, value: ["n": NSNull()], op: .merge))
        try await page.waitFor("document.getElementById('value').textContent === 'build:deleted'")
    }

    @Test func aNewSubscriberGetsTheHistoryThenEachNewValue() async throws {
        let channel = "\(prefix).series"
        for value in 1...3 { try ChannelHub.shared.publish(ChannelMessage(channel: channel, value: value)) }
        let source = """
            import { useSeries } from 'canvas'
            export default function App() {
              return <p id="series">{useSeries('\(channel)').join(',')}</p>
            }
            """
        _ = try await page.show(["source": source, "kind": "tsx"])
        defer { page.close() }
        try await page.waitFor("document.getElementById('series').textContent === '1,2,3'")
        try ChannelHub.shared.publish(ChannelMessage(channel: channel, value: 4))
        try await page.waitFor("document.getElementById('series').textContent === '1,2,3,4'")
    }

    @Test func thePageCanPublishExceptToReservedChannels() async throws {
        let channel = "\(prefix).pick"
        let source = """
            import { publish } from 'canvas'
            import { useEffect } from 'react'
            export default function App() {
              useEffect(() => {
                publish('canvas.sys.cpu', { total: 1 })
                publish('\(channel)', { pid: 7 })
              }, [])
              return <p>picker</p>
            }
            """
        _ = try await page.show(["source": source, "kind": "tsx"])
        defer { page.close() }
        try await waitUntil("the page publishes") { !page.published.isEmpty }
        #expect(page.published.map(\.channel) == [channel])
        #expect(canonical(ChannelHub.shared.store.latest(channel)) == #"{"pid":7}"#)
        #expect(ChannelHub.shared.store.latest("canvas.sys.cpu") == nil)
    }
}
