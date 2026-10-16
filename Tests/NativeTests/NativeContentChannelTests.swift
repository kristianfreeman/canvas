@testable import CanvasApp
import CanvasCore
import Foundation
import Testing
import TestSupport

/// Channels and the time limit through `NativePanelContent` and the real hub.
@MainActor @Suite(.serialized) struct NativeContentChannelTests {
    /// The hub is process-wide, so every run uses fresh channel names.
    private let prefix = "native.r\(UInt32.random(in: 0...UInt32.max))"

    @Test func historyComesFirstThenEachPublishReachesUseChannel() async throws {
        let probe = try ContentProbe()
        defer { probe.close() }
        let series = "\(prefix).series"
        let status = "\(prefix).status"
        for value in 1...3 { try ChannelHub.shared.publish(ChannelMessage(channel: series, value: value)) }
        _ = await probe.render(tsx: """
            import { Stack, Text, useChannel, useSeries } from 'canvas'
            export default function App() {
              const status = useChannel('\(status)')
              return <Stack><Text>{useSeries('\(series)').join(',')}</Text>
                <Text>{status === undefined ? 'none' : status.step}</Text></Stack>
            }
            """)
        try await probe.waitUntil("the history") { probe.text == "1,2,3|none" }
        try ChannelHub.shared.publish(ChannelMessage(channel: series, value: 4))
        try ChannelHub.shared.publish(ChannelMessage(channel: status, value: ["step": "build"]))
        try await probe.waitUntil("the new values") { probe.text == "1,2,3,4|build" }
    }

    @Test func aPushCommitReportsTheNewHeight() async throws {
        let probe = try ContentProbe()
        defer { probe.close() }
        let rows = "\(prefix).rows"
        let first = try #require(await probe.render(tsx: """
            import { Stack, Text, useChannel } from 'canvas'
            export default function App() {
              const rows = useChannel('\(rows)') ?? []
              return <Stack>{rows.map((row) => <Text key={row}>{row}</Text>)}</Stack>
            }
            """).height)
        try ChannelHub.shared.publish(ChannelMessage(channel: rows, value: (1...10).map(String.init)))
        try await probe.waitUntil("a taller height") { (probe.resizes.last ?? 0) > first + 9 * 16 }
    }

    @Test func publishGoesThroughTheHub() async throws {
        let probe = try ContentProbe()
        defer { probe.close() }
        let pick = "\(prefix).pick"
        _ = await probe.render(tsx: """
            import { Button, publish } from 'canvas'
            export default function App() { return <Button onClick={() => publish('\(pick)', { pid: 7 })}>go</Button> }
            """)
        probe.content.invoke(try probe.click("go"), [])
        try await probe.waitUntil("the publish") { ChannelHub.shared.store.latest(pick) != nil }
        #expect(canonical(ChannelHub.shared.store.latest(pick)) == #"{"pid":7}"#)
    }

    @Test func resetAndTearDownDropTheSubscriptions() async throws {
        let probe = try ContentProbe()
        defer { probe.close() }
        let channel = "\(prefix).a"
        let source = """
            import { Text, useChannel } from 'canvas'
            export default function App() { return <Text>{String(useChannel('\(channel)') ?? '')}</Text> }
            """
        _ = await probe.render(tsx: source)
        try await probe.waitUntil("the subscription") { ChannelHub.shared.store.subscriberCount(channel) == 1 }
        probe.content.reset()
        #expect(ChannelHub.shared.store.subscriberCount(channel) == 0)
        #expect(!ChannelHub.shared.isSubscribed(probe.content))
        #expect(probe.content.context == nil)
        _ = await probe.render(tsx: source)
        try await probe.waitUntil("the new subscription") { ChannelHub.shared.store.subscriberCount(channel) == 1 }
        probe.content.tearDown()
        #expect(ChannelHub.shared.store.subscriberCount(channel) == 0)
    }

    @Test func aRenderOverTheTimeLimitRetiresTheContextAndTheNextRenderWorks() async throws {
        let runtime = try NativeRuntime(webDir: Repo.webDir, timeLimit: 0.3)
        let probe = try ContentProbe(runtime: runtime)
        defer { probe.close() }
        let channel = "\(prefix).limit"
        _ = await probe.render(tsx: """
            import { Text, useChannel } from 'canvas'
            export default function App() { return <Text>{String(useChannel('\(channel)') ?? '')}</Text> }
            """)
        try await probe.waitUntil("the subscription") { ChannelHub.shared.isSubscribed(probe.content) }
        let stuck = try #require(probe.content.context)
        let result = await probe.render(tsx: "export default function App() { while (true) {} }")
        #expect(result.error?.contains("ran longer than 0.3 s") == true)
        #expect(probe.content.context != nil && probe.content.context !== stuck)
        #expect(!ChannelHub.shared.isSubscribed(probe.content))
        #expect(probe.content.tree.node(NativeErrorNodes.boxID)?.textContent.contains("ran longer") == true)
        let next = await probe.render(markdown: "# Later")
        #expect(next.error == nil, "\(next.error ?? "")")
        #expect(probe.content.tree.root.children.map(\.type) == ["Markdown"])
    }

    @Test func aTimerOverTheTimeLimitRetiresTheContextToo() async throws {
        let runtime = try NativeRuntime(webDir: Repo.webDir, timeLimit: 0.3)
        let probe = try ContentProbe(runtime: runtime)
        defer { probe.close() }
        _ = await probe.render(tsx: """
            import { Text } from 'canvas'
            import { useEffect } from 'react'
            export default function App() {
              useEffect(() => { setTimeout(() => { while (true) {} }, 10) }, [])
              return <Text>x</Text>
            }
            """)
        let stuck = try #require(probe.content.context)
        try await probe.waitUntil("the time limit error") { probe.errors.contains { $0.contains("ran longer") } }
        #expect(probe.content.context !== stuck)
        #expect(probe.content.tree.node(NativeErrorNodes.boxID) != nil)
    }
}
