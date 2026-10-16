import AppKit
@testable import CanvasApp
import Foundation
import Testing
import TestSupport

/// `canvas.render` and `canvas.setData` against the built page: what the
/// server gets back, and what ends up in the DOM.
@MainActor @Suite(.serialized) struct RenderBridgeTests {
    private let page = BridgePage()

    @Test func markdownRendersTheDocumentWithItsTitle() async throws {
        let source = """
            # Release *notes*

            | Area | Done |
            | --- | --- |
            | CLI | yes |

            - [x] tests
            - [ ] goldens

            ```swift
            let answer = 42
            ```

            A claim.[^1]

            [^1]: The source.
            """
        let result = try await page.show(["source": source, "title": "notes.md"])
        defer { page.close() }
        #expect(result.error == nil)
        let dom = try await page.evaluate("""
            const all = (s) => document.querySelectorAll('.cv-prose ' + s)
            return [all('h1')[0]?.textContent, all('h1 em').length, all('td').length,
                    all('input[type=checkbox]:checked').length, all('input[type=checkbox]').length,
                    all('pre code')[0]?.textContent.trim(), all('.footnotes li').length,
                    document.querySelector('.cv-title').textContent, document.querySelectorAll('.cv-app').length]
            """)
        let expected: [Any] = ["Release notes", 1, 2, 1, 2, "let answer = 42", 1, "notes.md", 0]
        #expect(canonical(dom) == canonical(expected))
    }

    @Test func rawHtmlInMarkdownStaysText() async throws {
        let result = try await page.show(["source": #"Say <b id="raw">hi</b> <img src=x onerror="alert(1)">"#])
        defer { page.close() }
        #expect(result.error == nil)
        #expect(try await page.evaluate("return document.querySelectorAll('#raw, .cv-prose img').length") as? Int == 0)
        let text = try await page.text(".cv-prose p")
        #expect(text.contains("<b id=") && text.contains(">hi</b>"), "\(text)")
    }

    @Test func tsxRendersTheDefaultExportWithItsDataProps() async throws {
        let source = """
            import { Stack } from 'canvas'
            type Props = { data: { name: string; items: string[] } }
            export default function App({ data }: Props) {
              return <Stack><h2 id="name">Hello, {data.name}</h2>
                <ul>{data.items.map((item) => <li key={item}>{item}</li>)}</ul></Stack>
            }
            """
        let result = try await page.show(
            ["source": source, "kind": "tsx", "data": ["name": "Kristian", "items": ["a", "b", "c"]]])
        defer { page.close() }
        #expect(result.error == nil)
        #expect(try await page.text("#name") == "Hello, Kristian")
        #expect(try await page.evaluate("return document.querySelectorAll('.cv-app li').length") as? Int == 3)
        #expect(try await page.evaluate("return document.querySelector('.cv-error') === null") as? Bool == true)
    }

    @Test func aTsxSyntaxErrorComesBackAsAnErrorAndShowsInThePanel() async throws {
        let result = try await page.show(["source": "export default function App() { return <div> }", "kind": "tsx"])
        defer { page.close() }
        let message = try #require(result.error)
        #expect(!message.isEmpty)
        #expect(try await page.text(".cv-error-message") == message)
        #expect((result.height ?? 0) > 40)
    }

    @Test func anExceptionWhileRenderingComesBackAsAnError() async throws {
        let source = "export default function App() { throw new Error('kaboom') }"
        let result = try await page.show(["source": source, "kind": "tsx"])
        defer { page.close() }
        #expect(result.error?.contains("kaboom") == true, "\(result.error ?? "no error")")
    }

    @Test func theHeightIsPlausibleGrowsWithContentAndCountsTheFooter() async throws {
        defer { page.close() }
        let short = try #require(try await page.show(["source": "One line."]).height)
        #expect(short > 60 && short < 300, "one line measured \(short)")
        let long = try #require(try await page.show(
            ["source": (1...40).map { "Paragraph \($0)." }.joined(separator: "\n\n")]).height)
        #expect(long > short + 40 * 16, "40 paragraphs measured \(long), one line \(short)")
        let footer = try #require(try await page.show(["source": "One line.", "buttons": ["OK"]]).height)
        #expect(footer > short + 24, "with a footer \(footer), without \(short)")
        try await waitUntil("the ResizeObserver reports \(footer)") { page.resizes.last == footer }
    }

    @Test func newDataRerendersWithoutRemountingAndReportsTheNewHeight() async throws {
        let source = """
            import { useState } from 'react'
            export default function App({ data }) {
              const [clicks, setClicks] = useState(0)
              return <div><button id="inc" onClick={() => setClicks(clicks + 1)}>+</button>
                <span id="clicks">{clicks}</span><ul>{data.rows.map((r) => <li key={r}>{r}</li>)}</ul></div>
            }
            """
        let first = try await page.show(["source": source, "kind": "tsx", "data": ["rows": [1]]])
        defer { page.close() }
        _ = try await page.evaluate("document.getElementById('inc').click()")
        try await page.waitFor("document.getElementById('clicks').textContent === '1'")
        let height = try #require(await page.setData(["rows": Array(1...20)]))
        #expect(try await page.evaluate("return document.querySelectorAll('li').length") as? Int == 20)
        #expect(try await page.text("#clicks") == "1")
        #expect(height > (first.height ?? 0) + 19 * 16, "20 rows measured \(height), 1 row \(first.height ?? 0)")
    }

    @Test func footerButtonsPutThePrimaryLastAndSubmitTheirLabel() async throws {
        _ = try await page.show(["source": "Ship it?", "buttons": ["Approve", "Reject"], "wait": true])
        defer { page.close() }
        let labels = try await page.evaluate(
            "return [...document.querySelectorAll('.cv-footer button')].map((b) => b.firstChild.textContent)")
        #expect(canonical(labels) == #"["Reject","Approve"]"#)
        _ = try await page.evaluate("document.querySelector('[data-canvas-primary]').click()")
        try await waitUntil("the primary button submits") { page.submitted.count == 1 }
        #expect(canonical(page.submitted) == #"["Approve"]"#)
    }

    @Test func themeAndAccentReachTheDocument() async throws {
        let accent = "return getComputedStyle(document.documentElement).getPropertyValue('--accent').trim()"
        _ = try await page.show(["source": "x", "theme": "light", "accent": "#ff0000"])
        defer { page.close() }
        #expect(try await page.evaluate("return document.documentElement.dataset.theme") as? String == "light")
        #expect(try await page.evaluate(accent) as? String == "#ff0000")
        _ = try await page.evaluate("canvas.setAccent('rgb(1, 2, 3)')")
        #expect(try await page.evaluate(accent) as? String == "rgb(1, 2, 3)")
        _ = try await page.show(["source": "x", "theme": "dark"])
        #expect(try await page.evaluate("return document.documentElement.dataset.theme") as? String == "dark")
        #expect(try await page.evaluate(accent) as? String != "rgb(1, 2, 3)")
    }
}

/// Polls a Swift-side condition while the main run loop delivers page
/// messages.
@MainActor func waitUntil(_ what: String, timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else { throw BridgeTimeout(description: "timed out waiting until \(what)") }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}
