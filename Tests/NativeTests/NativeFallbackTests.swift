@testable import CanvasApp
import CanvasCore
import Testing

/// Trees only WebKit can draw: `needsWeb`, and not one op reaches Swift.
@MainActor @Suite struct NativeFallbackTests {
    static let cases: [(String, String)] = [
        ("DOM tag", "<Stack><div>hi</div></Stack>"),
        ("className", "<Text className=\"big\">hi</Text>"),
        ("style key", "<Text style={{ lineHeight: '22px' }}>hi</Text>"),
        ("style value", "<Stack style={{ width: '50%' }} />"),
        ("size unit", "<Stack gap=\"1rem\" />"),
        ("grid tracks", "<Grid columns=\"repeat(3, 1fr)\" />"),
        ("svg", "<Card title={<svg />}>x</Card>")
    ]

    private static func source(_ jsx: String) -> String {
        """
        import { Card, Grid, Stack, Text } from 'canvas'
        export default function App() { return <Stack><Text>before</Text>\(jsx)</Stack> }
        """
    }

    @Test(arguments: cases)
    func fallsBackWithoutPostingOps(name: String, jsx: String) async throws {
        let page = try NativeHarness()
        defer { page.close() }
        let result = await page.render(tsx: Self.source(jsx))
        #expect(result.needsWeb, "\(name): \(result.error ?? "ok")")
        #expect(result.error?.isEmpty == false)
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(page.batches == 0, "\(name) posted ops")
        #expect(page.tree.root.children.isEmpty)
    }

    @Test func reactDomImportsFallBack() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        let source = "import { createPortal } from 'react-dom'\nexport default () => createPortal"
        let result = await page.render(tsx: source)
        #expect(result.needsWeb)
        #expect(page.batches == 0)
    }

    @Test func anErrorBoundaryCannotCommitAPartialTree() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        let result = await page.render(tsx: """
        import { Component } from 'react'
        import { Text } from 'canvas'
        class Boundary extends Component<{ children: any }, { failed: boolean }> {
          state = { failed: false }
          static getDerivedStateFromError() { return { failed: true } }
          render() { return this.state.failed ? <Text>caught</Text> : this.props.children }
        }
        export default function App() { return <Boundary><span>x</span></Boundary> }
        """)
        #expect(result.needsWeb)
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(page.batches == 0)
        #expect(page.tree.root.children.isEmpty)
    }

    @Test func theRenderAfterAFallbackClearsWhatTheTreeStillShows() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(markdown: "# One")
        #expect(page.tree.root.children.map(\.type) == ["Markdown"])
        let fallback = await page.render(tsx: Self.source("<div />"))
        #expect(fallback.needsWeb)
        #expect(page.tree.root.children.map(\.type) == ["Markdown"])
        let next = await page.render(markdown: "# Three")
        #expect(next.ok)
        #expect(page.tree.root.children.count == 1)
        #expect(page.tree.count == 1)
        #expect(page.host.lastError == nil)
    }

    @Test func aDomTagAfterTheFirstRenderIsReportedAsNeedingWeb() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: """
        import { Button, Text } from 'canvas'
        import { useState } from 'react'
        export default function App() {
          const [raw, setRaw] = useState(false)
          return raw ? <p>raw</p> : <Button onClick={() => setRaw(true)}>go</Button>
        }
        """)
        let batches = page.batches
        let result = await page.invoke(try #require(page.function("Button", "onClick")))
        #expect(result.needsWeb)
        #expect(page.batches == batches)
        try await page.waitUntil("needsWeb error") {
            page.messages.contains { if case .error(_, _, true) = $0 { true } else { false } }
        }
    }
}
