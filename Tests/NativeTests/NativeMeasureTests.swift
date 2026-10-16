@testable import CanvasApp
import CanvasCore
import Darwin
import Foundation
import TestSupport
import Testing

/// Timings and memory for the native runtime, printed rather than asserted.
/// Run alone: `CANVAS_MEASURE=1 swift test --filter NativeMeasureTests`.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["CANVAS_MEASURE"] == "1"))
struct NativeMeasureTests {
    private static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    private static func milliseconds(_ result: NativeResult) -> Double {
        Clock.milliseconds(from: result.jsStart, to: result.jsEnd)
    }

    private static func median(_ values: [Double]) -> Double {
        values.sorted()[values.count / 2]
    }

    private static func approve() throws -> String {
        let source = try String(contentsOf: Repo.examples.appendingPathComponent("approve.tsx"), encoding: .utf8)
        return source.replacingOccurrences(of: " style={{ lineHeight: '22px' }}", with: "")
    }

    private static func hello() throws -> String {
        try String(contentsOf: Repo.examples.appendingPathComponent("hello.md"), encoding: .utf8)
    }

    private static func report(_ name: String, _ value: Double, _ unit: String) {
        print("measure: \(name) = \(String(format: "%.1f", value)) \(unit)")
    }

    /// A new context, waited on until its bundle is evaluated.
    private static func evaluated(_ runtime: NativeRuntime, _ name: String) async throws -> NativeHarness {
        let started = Clock.now()
        let page = try NativeHarness(runtime: runtime)
        _ = await page.setData(NSNull())
        report("\(name): created and bundle evaluated (wall)", Clock.milliseconds(from: started, to: Clock.now()), "ms")
        return page
    }

    private static func warmed(_ page: NativeHarness) async {
        let started = Clock.now()
        _ = await withCheckedContinuation { done in page.context.warm { done.resume(returning: $0) } }
        report("warm()", Clock.milliseconds(from: started, to: Clock.now()), "ms")
    }

    @Test func contextCostAndRenderTimes() async throws {
        let runtime = try NativeHarness.runtime()
        let before = Self.footprint()
        let first = try await Self.evaluated(runtime, "context 1 (first in process)")
        let one = Self.footprint()
        Self.report("phys_footprint delta, context 1 (includes VM setup)", one - before, "MB")
        let second = try await Self.evaluated(runtime, "context 2")
        let two = Self.footprint()
        Self.report("phys_footprint delta, context 2", two - one, "MB")
        let third = try await Self.evaluated(runtime, "context 3")
        Self.report("phys_footprint delta, context 3", Self.footprint() - two, "MB")

        let cold = await first.render(tsx: try Self.approve())
        #expect(cold.ok, "\(cold.error ?? "")")
        Self.report("approve.tsx cold render, unwarmed context (js)", Self.milliseconds(cold), "ms")
        let coldMarkdown = await second.render(markdown: try Self.hello())
        Self.report("hello.md cold render, unwarmed context (js)", Self.milliseconds(coldMarkdown), "ms")
        Self.report("phys_footprint, 3 contexts, 2 rendered", Self.footprint() - before, "MB")

        await Self.warmed(third)
        let afterWarm = await third.render(tsx: try Self.approve())
        Self.report("approve.tsx first render after warm() (js)", Self.milliseconds(afterWarm), "ms")
        try await measureWarm(third)
        [first, second, third].forEach { $0.close() }
    }

    private func measureWarm(_ page: NativeHarness) async throws {
        var tsx: [Double] = []
        var markdown: [Double] = []
        var setData: [Double] = []
        var wall: [Double] = []
        for index in 0..<15 {
            let started = Clock.now()
            tsx.append(Self.milliseconds(await page.render(tsx: try Self.approve())))
            wall.append(Clock.milliseconds(from: started, to: Clock.now()))
            setData.append(Self.milliseconds(await page.setData(["title": "Deploy \(index)"])))
            markdown.append(Self.milliseconds(await page.render(markdown: try Self.hello() + "\n\(index)")))
        }
        Self.report("approve.tsx warm render (js, median)", Self.median(tsx), "ms")
        Self.report("approve.tsx warm render (main to main, median)", Self.median(wall), "ms")
        Self.report("approve.tsx setData (js, median)", Self.median(setData), "ms")
        Self.report("hello.md warm render, uncached (js, median)", Self.median(markdown), "ms")
        Self.report("tree nodes for hello.md", Double(page.tree.count), "")
    }
}
