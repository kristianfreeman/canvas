@testable import CanvasApp
import CanvasCore
import TestSupport
import Testing

/// Calls that run past the limit are stopped and reported, on their own VM.
@MainActor @Suite struct NativeTimeLimitTests {
    private static func runtime() throws -> NativeRuntime {
        try NativeRuntime(webDir: Repo.webDir, timeLimit: 0.3)
    }

    @Test func theLimitIsAvailable() {
        #expect(NativeTimeLimit.isAvailable)
    }

    @Test func anEndlessRenderIsStoppedAndTheContextRetired() async throws {
        let page = try NativeHarness(runtime: Self.runtime())
        defer { page.close() }
        let source = "import { Text } from 'canvas'\nexport default function App() { while (true) {} return <Text /> }"
        let started = Clock.now()
        let result = await page.render(tsx: source)
        let elapsed = Clock.milliseconds(from: started, to: Clock.now())
        #expect(result.timedOut)
        #expect(result.error?.contains("ran longer than 0.3 s") == true)
        #expect(elapsed < 2_000, "took \(elapsed) ms")
        let after = await page.render(markdown: "# Later")
        #expect(after.error == result.error)
        #expect(page.batches == 0)
    }

    @Test func anEndlessTimerIsStoppedAndReported() async throws {
        let page = try NativeHarness(runtime: Self.runtime())
        defer { page.close() }
        _ = await page.render(tsx: """
        import { Text } from 'canvas'
        import { useEffect } from 'react'
        export default function App() {
          useEffect(() => { setTimeout(() => { while (true) {} }, 10) }, [])
          return <Text>x</Text>
        }
        """)
        try await page.waitUntil("time limit error") { page.errors.contains { $0.contains("ran longer") } }
    }

    @Test func otherContextsOnTheSameMachineKeepWorking() async throws {
        let runtime = try Self.runtime()
        let stuck = try NativeHarness(runtime: runtime)
        let fine = try NativeHarness(runtime: runtime)
        defer {
            stuck.close()
            fine.close()
        }
        _ = await stuck.render(tsx: "export default function App() { for (;;) {} }")
        let result = await fine.render(markdown: "# Still here")
        #expect(result.ok, "\(result.error ?? "")")
        #expect(fine.node("Markdown") != nil)
    }
}
