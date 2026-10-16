@testable import CanvasApp
import CanvasCore
import Foundation
import TestSupport
import Testing

/// Request-to-ready for a warm native show through `NativePanelContent`:
/// the parked content exists and its context is evaluated and warmed, as
/// the server keeps them. Printed, not asserted. Run alone, in a fresh
/// process, since SwiftUI's one-time costs are paid once per process:
///
///     CANVAS_MEASURE=1 swift test --filter NativeShowMeasureTests
///     CANVAS_MEASURE=1 CANVAS_MEASURE_PREWARM=0 swift test --filter NativeShowMeasureTests
@MainActor @Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CANVAS_MEASURE"] == "1"))
struct NativeShowMeasureTests {
    static let kitTSX = """
        import { Badge, Card, Grid, Progress, Row, Sparkline, Stack, Stat, Table, Text } from 'canvas'
        export default function Dashboard({ data }) {
          const rows = data?.rows ?? [['api', 'v2.14.0', 'live'], ['web', 'v8.3.1', 'rolling']]
          return <Stack gap={14}>
            <Grid columns={2} gap={12}>
              <Card><Stat label="Deploys" value="48" delta="+12%" /><Sparkline data={[4, 6, 5, 7, 9]} /></Card>
              <Card><Stat label="p95 build" value="6m 12s" delta="-38s" invertDelta /></Card>
            </Grid>
            <Card title="Error budget"><Progress label="api" value={72} max={100} color="green" showValue /></Card>
            <Table columns={[{ key: 'service' }, { key: 'version' }, { key: 'status', align: 'right' }]}
              rows={rows.map(([service, version, status]) => ({
                service, version, status: <Badge dot>{status}</Badge>
              }))} />
            <Row gap={8}><Text muted size="sm">production</Text></Row>
          </Stack>
        }
        """

    private static func report(_ name: String, _ value: Double) {
        print("measure: \(name) = \(String(format: "%.2f", value)) ms")
    }

    private static func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

    /// A context with the bundle evaluated and `warm()` done.
    private static func warmedContext(_ runtime: NativeRuntime) async -> NativeContext {
        let context = runtime.makeContext()
        _ = await withCheckedContinuation { done in context.warm { done.resume(returning: $0) } }
        return context
    }

    /// One show: render on a parked content until the height is measured.
    private static func show(_ payload: [String: Any], runtime: NativeRuntime) async -> (wall: Double, js: Double) {
        let context = await warmedContext(runtime)
        let content = NativePanelContent(contexts: { context })
        defer { content.tearDown() }
        let started = Clock.now()
        let result = await withCheckedContinuation { done in content.render(payload) { done.resume(returning: $0) } }
        let wall = Clock.milliseconds(from: started, to: Clock.now())
        #expect(result.error == nil, "\(result.error ?? "")")
        #expect((result.height ?? 0) > 0)
        return (wall, Clock.milliseconds(from: result.jsStart ?? 0, to: result.jsEnd ?? 0))
    }

    private static var hello: [String: Any] {
        let source = (try? String(contentsOf: Repo.examples.appendingPathComponent("hello.md"), encoding: .utf8)) ?? ""
        return ["kind": "markdown", "source": source, "title": "hello.md", "wait": false]
    }

    private static let kit: [String: Any] = ["kind": "tsx", "source": kitTSX, "title": "dashboard", "wait": false]

    /// The Hyper+I cheat sheet.
    private static var keys: [String: Any] {
        let source = (try? String(contentsOf: Repo.examples.appendingPathComponent("keys.tsx"), encoding: .utf8)) ?? ""
        let json = (try? Data(contentsOf: Repo.examples.appendingPathComponent("keys.json"))) ?? Data()
        let data = (try? JSONSerialization.jsonObject(with: json)) ?? [:]
        return ["kind": "tsx", "source": source, "data": data, "title": "Shortcuts", "wait": false]
    }

    @Test func firstShowInTheProcessThenWarmShows() async throws {
        let runtime = try NativeHarness.runtime()
        if ProcessInfo.processInfo.environment["CANVAS_MEASURE_PREWARM"] != "0" {
            Self.report("SwiftUI prewarm (every kit type, dark and light)", NativePrewarm.run())
        }
        let first = await Self.show(Self.kit, runtime: runtime)
        Self.report("first kit TSX show in the process, request to ready", first.wall)
        Self.report("first kit TSX show, outside JS (ops, SwiftUI layout, hops)", first.wall - first.js)
        let firstHello = await Self.show(Self.hello, runtime: runtime)
        Self.report("first hello.md show, request to ready", firstHello.wall)

        for (name, payload) in [("kit TSX", Self.kit), ("hello.md", Self.hello), ("keys.tsx", Self.keys)] {
            var walls: [Double] = []
            var scripts: [Double] = []
            for _ in 0..<12 {
                let (wall, js) = await Self.show(payload, runtime: runtime)
                walls.append(wall)
                scripts.append(js)
            }
            Self.report("warm \(name) show, request to ready (median of 12)", Self.median(walls))
            Self.report("warm \(name) show, of which JS (median of 12)", Self.median(scripts))
        }
    }
}
