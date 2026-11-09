@testable import CanvasApp
import CanvasCore
import TestSupport
import Testing

/// Task checkboxes in Markdown and `useStore`, through a real context.
@MainActor @Suite struct NativeTaskTests {
    private static func tasks(_ page: NativeHarness) -> [String] {
        page.messages.compactMap { message in
            guard case .task(let line, let checked) = message else { return nil }
            return "\(line)=\(checked)"
        }
    }

    private static func items(_ page: NativeHarness) throws -> [MarkdownListItem] {
        let blocks = MarkdownBlocks.decode(try #require(page.node("Markdown")).prop("blocks"))
        return blocks.flatMap { block -> [MarkdownListItem] in
            guard case .list(let list) = block else { return [] }
            return list.items
        }
    }

    @Test func aMarkdownPanelsToggleNamesTheLine() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(markdown: "# Today\n\n- [ ] one\n- [x] two\n")
        #expect(try Self.items(page).map(\.line) == [2, 3])
        let toggle = try #require(page.function("Markdown", "onToggle"))
        #expect(await page.invoke(toggle, [["line": 3, "checked": false]]).ok)
        #expect(Self.tasks(page) == ["3=false"])
    }

    @Test func tsxMarkdownTogglesOnlyWithOnToggle() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: """
        import { Markdown, Stack } from 'canvas'
        import { useState } from 'react'
        export default function App() {
          const [source, setSource] = useState('- [ ] a\\n- [ ] b\\n')
          return (
            <Stack>
              <Markdown source="- [ ] read only" />
              <Markdown source={source} onToggle={({ line, checked }) => setSource(source.split('\\n')
                .map((text, i) => i === line ? text.replace(/\\[.\\]/, checked ? '[x]' : '[ ]') : text)
                .join('\\n'))} />
            </Stack>
          )
        }
        """)
        let markdowns = page.nodes("Markdown")
        #expect(markdowns.count == 2)
        #expect(markdowns[0].props["onToggle"] == nil)
        let toggle = try #require(markdowns[1].props["onToggle"]?.function)
        _ = await page.invoke(toggle, [["line": 1, "checked": true]])
        let blocks = MarkdownBlocks.decode(page.nodes("Markdown")[1].prop("blocks"))
        guard case .list(let list) = blocks.first else { throw NativeTimeout(description: "no list") }
        #expect(list.items.map(\.checked) == [false, true])
        #expect(Self.tasks(page).isEmpty)
    }

    @Test func useStoreShowsTheSetAtOnceAndPublishesPersisted() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: """
        import { Button, Text, useStore } from 'canvas'
        export default function App() {
          const [count, setCount] = useStore('demo.count', 5)
          return <Button onClick={() => setCount((n) => n + 1)}><Text>{`count ${count}`}</Text></Button>
        }
        """)
        #expect(page.node("Text")?.textContent == "count 5")
        let subscribed = page.messages.contains { message in
            if case .subscribe("demo.count", _) = message { return true }
            return false
        }
        #expect(subscribed)

        _ = await page.invoke(try #require(page.function("Button", "onClick")))
        #expect(page.node("Text")?.textContent == "count 6")
        let published = page.messages.compactMap { message -> String? in
            guard case .publish(let channel, let value, let persist) = message else { return nil }
            return "\(channel)=\(canonical(value)) persist=\(persist)"
        }
        #expect(published == ["demo.count=6 persist=true"])

        _ = await page.push([["channel": "demo.count", "value": 40]])
        #expect(page.node("Text")?.textContent == "count 40")
        _ = await page.invoke(try #require(page.function("Button", "onClick")))
        #expect(page.node("Text")?.textContent == "count 41")
    }
}
