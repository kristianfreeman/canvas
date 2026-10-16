@testable import CanvasApp
import CanvasCore
import Foundation
import Testing
import TestSupport

/// Real TSX and Markdown through `NativePanelContent`, the content a native
/// panel shows, with no window.
@MainActor @Suite(.serialized) struct NativePanelContentTests {
    @Test func theHeightCountsHeaderContentAndFooterAndGrowsWithContent() async throws {
        let probe = try ContentProbe()
        defer { probe.close() }
        let short = try #require(await probe.render(markdown: "One line.").height)
        #expect(short > 60 && short < 200, "one line measured \(short)")
        let long = try #require(await probe.render(
            markdown: (1...30).map { "Paragraph \($0)." }.joined(separator: "\n\n")).height)
        #expect(long > short + 30 * 16, "30 paragraphs measured \(long), one line \(short)")
        let footer = try #require(await probe.render(markdown: "One line.", buttons: ["OK"]).height)
        #expect(footer > short + 24, "with a footer \(footer), without \(short)")
    }

    /// A panel with timers pending doesn't rest when closed, so it must say so.
    @Test func pendingTimersAreReportedUntilTheyAreDone() async throws {
        let probe = try ContentProbe()
        defer { probe.close() }
        _ = await probe.render(markdown: "Static.")
        #expect(!probe.content.hasTimers, "a static page left a timer pending")
        _ = await probe.render(tsx: """
            import { Text } from 'canvas'
            import { useEffect, useState } from 'react'
            export default function App() {
              const [done, setDone] = useState(false)
              useEffect(() => { setTimeout(() => setDone(true), 20) }, [])
              return <Text>{done ? 'done' : 'waiting'}</Text>
            }
            """)
        #expect(probe.content.hasTimers, "a pending setTimeout wasn't reported")
        try await probe.waitUntil("the timeout") { probe.text == "done" }
        #expect(!probe.content.hasTimers, "a fired setTimeout was still reported")
        _ = await probe.render(tsx: """
            import { Text } from 'canvas'
            import { useEffect } from 'react'
            export default function App() {
              useEffect(() => { setInterval(() => {}, 1000) }, [])
              return <Text>clock</Text>
            }
            """)
        #expect(probe.content.hasTimers, "a running setInterval wasn't reported")
    }

    @Test func aNarrowerPanelReportsATallerHeight() async throws {
        let probe = try ContentProbe(width: 640)
        defer { probe.close() }
        let wide = try #require(await probe.render(markdown: String(repeating: "word ", count: 120)).height)
        probe.content.view.setFrameSize(NSSize(width: 320, height: 400))
        try await probe.waitUntil("a resize after the width change") { !probe.resizes.isEmpty }
        #expect(try #require(probe.resizes.last) > wide + 40)
    }

    @Test func eventsReachTheContextAndResultsAndClosesTheDelegate() async throws {
        let probe = try ContentProbe()
        defer { probe.close() }
        let first = try #require(await probe.render(tsx: """
            import { Button, Stack, Text, useCanvas } from 'canvas'
            import { useState } from 'react'
            export default function App() {
              const canvas = useCanvas()
              const [n, setN] = useState(0)
              return <Stack>
                <Button onClick={() => setN(n + 1)}>more</Button>
                {Array.from({ length: n }, (_, i) => <Text key={i}>{`row ${i}`}</Text>)}
                <Button onClick={() => canvas.submit({ n })}>done</Button>
                <Button onClick={() => canvas.close()}>close</Button>
              </Stack>
            }
            """).height)
        probe.content.invoke(try probe.click("more"), [])
        probe.content.invoke(try probe.click("more"), [])
        try await probe.waitUntil("two rows") { probe.text == "row 0|row 1" }
        try await probe.waitUntil("a taller height") { (probe.resizes.last ?? 0) > first + 30 }
        probe.content.invoke(try probe.click("done"), [])
        try await probe.waitUntil("the result") { !probe.submitted.isEmpty }
        #expect(canonical(probe.submitted) == #"[{"n":2}]"#)
        probe.content.invoke(try probe.click("close"), [])
        try await probe.waitUntil("the close") { !probe.closes.isEmpty }
        probe.content.submit("Approve")
        probe.content.close()
        #expect(canonical(probe.submitted.last) == #""Approve""#)
        #expect(probe.closes == ["close", "close"])
    }

    @Test func aDomTreeAtTheFirstRenderComesBackAsNeedsWeb() async throws {
        let probe = try ContentProbe()
        defer { probe.close() }
        let result = await probe.render(tsx: "export default function App() { return <div>hi</div> }")
        #expect(result.needsWeb)
        #expect(result.height == nil)
        #expect(probe.content.tree.root.children.isEmpty, "the error box must not show for a fallback")
        #expect(probe.needsWeb == 0, "the render result carries the first fallback")
    }

    @Test func aDomTreeAfterAnEventSignalsTheFallbackOnce() async throws {
        let probe = try ContentProbe()
        defer { probe.close() }
        _ = await probe.render(tsx: """
            import { Button } from 'canvas'
            import { useState } from 'react'
            export default function App() {
              const [raw, setRaw] = useState(false)
              return raw ? <p>raw</p> : <Button onClick={() => setRaw(true)}>go</Button>
            }
            """)
        let go = try probe.click("go")
        probe.content.invoke(go, [])
        probe.content.invoke(go, [])
        try await probe.waitUntil("the fallback signal") { probe.needsWeb > 0 }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(probe.needsWeb == 1)
        #expect(probe.errors.isEmpty, "\(probe.errors)")
    }

    @Test func setDataReRendersKeepingState() async throws {
        let probe = try ContentProbe()
        defer { probe.close() }
        let first = try #require(await probe.render(tsx: """
            import { Button, Stack, Text } from 'canvas'
            import { useState } from 'react'
            export default function App({ data }) {
              const [clicks, setClicks] = useState(0)
              return <Stack><Button onClick={() => setClicks(clicks + 1)}>+</Button>
                <Text>{`clicks ${clicks}`}</Text>
                {data.rows.map((row) => <Text key={row}>{`row ${row}`}</Text>)}</Stack>
            }
            """, data: ["rows": [1]]).height)
        probe.content.invoke(try probe.click("+"), [])
        try await probe.waitUntil("one click") { probe.text.hasPrefix("clicks 1") }
        let height = try #require(await probe.setData(["rows": Array(1...12)]))
        #expect(probe.nodes("Text").count == 13)
        #expect(probe.text.hasPrefix("clicks 1|row 1"))
        #expect(height > first + 11 * 16, "12 rows measured \(height), 1 row \(first)")
    }

    @Test func aRenderErrorShowsInThePanelUntilTheNextRender() async throws {
        let probe = try ContentProbe()
        defer { probe.close() }
        let result = await probe.render(tsx: "export default function App() { throw new Error('kaboom') }")
        let message = try #require(result.error)
        #expect(message.contains("kaboom"))
        #expect(probe.content.tree.node(NativeErrorNodes.boxID)?.textContent.contains("kaboom") == true)
        #expect((result.height ?? 0) > 80)
        let next = await probe.render(markdown: "# Fine")
        #expect(next.error == nil)
        #expect(probe.content.tree.node(NativeErrorNodes.boxID) == nil)
        #expect(probe.content.tree.root.children.map(\.type) == ["Markdown"])
    }

    @Test func themeFollowsModeAndAccent() async throws {
        let probe = try ContentProbe()
        defer { probe.close() }
        _ = await probe.render(["kind": "markdown", "source": "x", "wait": false, "accent": "#ff0000"])
        probe.content.setMode(.light)
        #expect(probe.content.surface.theme == Theme(mode: .light, accent: "#ff0000"))
        probe.content.setAccent("#00ff00")
        #expect(probe.content.surface.theme == Theme(mode: .light, accent: "#00ff00"))
    }
}
