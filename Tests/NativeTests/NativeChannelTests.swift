@testable import CanvasApp
import CanvasCore
import TestSupport
import Testing

/// Channel hooks through a real context: subscribe messages, push, publish.
@MainActor @Suite struct NativeChannelTests {
    @Test func useChannelSubscribesAndPushReRenders() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: """
        import { Text, useChannel, useSeries } from 'canvas'
        export default function App() {
          const cpu = useChannel<{ total: number }>('canvas.sys.cpu', { every: 250 })
          const series = useSeries<number>('demo.value', 3)
          return <Text>{`${cpu?.total ?? '-'} ${series.join(',')}`}</Text>
        }
        """)
        let subscribed = page.messages.compactMap { message -> String? in
            guard case .subscribe(let channel, let every) = message else { return nil }
            return "\(channel)@\(every.map(String.init) ?? "-")"
        }
        #expect(Set(subscribed) == ["canvas.sys.cpu@250", "demo.value@-"])
        #expect(page.node("Text")?.textContent == "- ")

        _ = await page.push([["channel": "canvas.sys.cpu", "value": ["total": 0.5]],
                             ["channel": "demo.value", "value": 3, "history": [1, 2, 3]]])
        #expect(page.node("Text")?.textContent == "0.5 1,2,3")
        _ = await page.push([["channel": "demo.value", "value": 4]])
        #expect(page.node("Text")?.textContent == "0.5 2,3,4")
    }

    @Test func publishPostsExceptToReservedChannels() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: """
        import { Button, publish, useCanvas } from 'canvas'
        export default function App() {
          const canvas = useCanvas()
          return <Button onClick={() => {
            publish('canvas.sys.cpu', 1)
            publish('canvas', 2)
            canvas.publish('top.select', { pid: 7 })
          }}>x</Button>
        }
        """)
        _ = await page.invoke(try #require(page.function("Button", "onClick")))
        let published = page.messages.compactMap { message -> String? in
            guard case .publish(let channel, let value) = message else { return nil }
            return "\(channel)=\(canonical(value))"
        }
        #expect(published == [#"top.select={"pid":7}"#])
    }

    @Test func resetUnsubscribes() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: """
        import { Text, useChannel } from 'canvas'
        export default function App() { return <Text>{String(useChannel('demo.a') ?? '')}</Text> }
        """)
        _ = await page.reset()
        try await page.waitUntil("unsubscribe") {
            page.messages.contains { if case .unsubscribe("demo.a") = $0 { true } else { false } }
        }
    }
}
