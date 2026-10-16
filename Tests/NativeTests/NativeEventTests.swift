@testable import CanvasApp
import CanvasCore
import TestSupport
import Testing

/// Function props, setData and timers through a real context.
@MainActor @Suite struct NativeEventTests {
    static let counter = """
    import { Button, Stack, Text, useCanvas } from 'canvas'
    import { useState } from 'react'
    export default function Counter({ data }: { data: { title: string } }) {
      const [count, setCount] = useState(0)
      const { submit } = useCanvas()
      return (
        <Stack>
          <Text>{data.title}</Text>
          <Text>{`count ${count}`}</Text>
          <Button onClick={() => setCount(count + 1)}>add</Button>
          <Button variant="primary" onClick={() => submit({ title: data.title, count })}>send</Button>
        </Stack>
      )
    }
    """

    private static func texts(_ page: NativeHarness) -> [String] {
        page.nodes("Text").map(\.textContent)
    }

    @Test func invokeCallsTheLatestHandlerAndKeepsItsId() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: Self.counter, data: ["title": "a"])
        let add = try #require(page.function("Button", "onClick"))
        #expect(await page.invoke(add).ok)
        #expect(await page.invoke(add).ok)
        #expect(Self.texts(page) == ["a", "count 2"])
        #expect(page.function("Button", "onClick") == add)
    }

    @Test func setDataKeepsStateAndHandlersSeeTheNewData() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: Self.counter, data: ["title": "a"])
        _ = await page.invoke(try #require(page.function("Button", "onClick")))
        #expect(await page.setData(["title": "b"]).ok)
        #expect(Self.texts(page) == ["b", "count 1"])
        let send = try #require(page.nodes("Button").last?.props["onClick"]?.function)
        _ = await page.invoke(send)
        #expect(canonical(page.results.last) == #"{"count":1,"title":"b"}"#)
    }

    @Test func onChangeHandlersGetAnEventWithTheValue() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: """
        import { Checkbox, Input, Text } from 'canvas'
        import { useState } from 'react'
        export default function App() {
          const [text, setText] = useState('')
          const [on, setOn] = useState(false)
          return <>
            <Input name="q" value={text} onChange={(e) => setText(e.target.value)} />
            <Checkbox name="c" checked={on} onChange={(e) => setOn(e.target.checked)} label="On" />
            <Text>{`${text}/${on}`}</Text>
          </>
        }
        """)
        _ = await page.invoke(try #require(page.function("Input", "onChange")), [["value": "hey"]])
        _ = await page.invoke(try #require(page.function("Checkbox", "onChange")), [["checked": true]])
        #expect(page.node("Text")?.textContent == "hey/true")
        #expect(page.node("Input")?.props["value"] == .string("hey"))
    }

    @Test func formsAndValueButtonsSubmitThroughFunctionProps() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: """
        import { Button, Form, Input } from 'canvas'
        export default function App() {
          return <>
            <Form><Input name="q" /><Button name="go" value="yes">Go</Button></Form>
            <Button value={{ pick: 2 }}>Pick</Button>
          </>
        }
        """)
        let buttons = page.nodes("Button")
        #expect(buttons.map { $0.props["submit"] } == [.bool(true), .bool(false)])
        #expect(buttons.first?.props["onClick"] == nil)
        _ = await page.invoke(try #require(page.function("Form", "onSubmit")), [["q": "x", "go": "yes"]])
        _ = await page.invoke(try #require(buttons.last?.props["onClick"]?.function))
        #expect(page.results.map { canonical($0) } == [#"{"go":"yes","q":"x"}"#, #"{"pick":2}"#])
    }

    @Test func aHandlerErrorIsPostedAndUnmountsTheTree() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: """
        import { Button } from 'canvas'
        import { useState } from 'react'
        export default function App() {
          const [boom, setBoom] = useState(false)
          if (boom) throw new Error('kaboom')
          return <Button onClick={() => setBoom(true)}>x</Button>
        }
        """)
        let result = await page.invoke(try #require(page.function("Button", "onClick")))
        #expect(result.error == "kaboom")
        #expect(page.errors == ["kaboom"])
        #expect(page.tree.root.children.isEmpty)
        #expect(page.nodes("Button").isEmpty)
    }

    @Test func effectTimersFireAndReRender() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: """
        import { Text } from 'canvas'
        import { useEffect, useState } from 'react'
        export default function App() {
          const [ticks, setTicks] = useState(0)
          const [done, setDone] = useState(false)
          useEffect(() => { const t = setTimeout(() => setDone(true), 20); return () => clearTimeout(t) }, [])
          useEffect(() => {
            const t = setInterval(() => setTicks((n) => n + 1), 10)
            return () => clearInterval(t)
          }, [])
          return <Text>{done ? `done ${ticks > 0}` : 'waiting'}</Text>
        }
        """)
        #expect(page.node("Text")?.textContent == "waiting")
        try await page.waitUntil("timeout") { page.node("Text")?.textContent == "done true" }
        _ = await page.reset()
        let batches = page.batches
        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(page.batches == batches, "an interval kept running after reset")
    }
}
