@testable import CanvasApp
import CanvasCore
import Testing

/// Kit TSX through a real context: host types, derived props and slots.
@MainActor @Suite struct NativeRenderTests {
    static let dashboard = """
    import { Badge, BarChart, Card, Grid, Progress, Stack, Stat, Table, Text } from 'canvas'
    export default function App({ data }: { data: { load: number } }) {
      return (
        <Stack gap="8px">
          <Card title="CPU" subtitle={<Badge color="green" dot>ok</Badge>} padding={20}
                style={{ marginTop: 4, textAlign: 'center' }}>
            <Stat label="Load" value={data.load} delta="-3%" invertDelta hint="1 min" />
          </Card>
          <Progress value={30} max={60} label="Disk" showValue />
          <Table
            columns={['name', { key: 'cpu', align: 'right', width: '80px', render: (row) => `${row.cpu}%` }]}
            rows={[{ id: 'a', name: 'x', cpu: 5 }, { name: 'y', cpu: 7 }]}
          />
          <BarChart data={[{ label: 'a', value: 2 }, { label: 'b', value: 4, color: 'red' }]} format={(v) => `${v}!`} />
          <Grid columns="max-content 1fr"><Text weight="semibold" muted>k</Text></Grid>
        </Stack>
      )
    }
    """

    @Test func kitComponentsBecomeHostElementsWithSlots() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        let result = await page.render(tsx: Self.dashboard, data: ["load": 42])
        #expect(result.ok, "\(result.error ?? "")")
        #expect(page.tree.root.children.map(\.type) == ["Stack"])
        #expect(page.node("Stack")?.props["gap"] == .number(8))

        let card = try #require(page.node("Card"))
        #expect(card.props["padding"] == .number(20))
        #expect(card.props["style"] == .object(["marginTop": .number(4), "textAlign": .string("center")]))
        #expect(card.slot("title")?.map(\.textContent) == ["CPU"])
        let badge = try #require(card.slot("subtitle")?.first)
        #expect(badge.type == "Badge")
        #expect(badge.props["color"] == .string("green"))
        #expect(badge.props["dot"] == .bool(true))
        #expect(card.body.map(\.type) == ["Stat"])
    }

    @Test func statDeltaToneAndGoodnessAreDerived() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: Self.dashboard, data: ["load": 42])
        let stat = try #require(page.node("Stat"))
        #expect(stat.props["tone"] == .string("down"))
        #expect(stat.props["good"] == .bool(true))
        #expect(stat.props["delta"] == .string("3%"))
        #expect(stat.slot("label")?.first?.textContent == "Load")
        #expect(stat.slot("value")?.first?.textContent == "42")
        #expect(stat.slot("hint")?.first?.textContent == "1 min")
    }

    @Test func progressIsNormalizedByMax() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: Self.dashboard, data: ["load": 1])
        let progress = try #require(page.node("Progress"))
        #expect(progress.props["value"] == .number(0.5))
        #expect(progress.props["showValue"] == .bool(true))
        #expect(progress.slot("label")?.first?.textContent == "Disk")
    }

    @Test func tableHasHeadCellsAndKeyedRowsWithRenderedColumns() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: Self.dashboard, data: ["load": 1])
        let table = try #require(page.node("Table"))
        #expect(table.props["columns"] == .array([
            .object(["key": .string("name")]),
            .object(["key": .string("cpu"), "align": .string("right"), "width": .number(80)])
        ]))
        #expect(table.slot("head")?.map(\.type) == ["TableCell", "TableCell"])
        #expect(table.slot("head")?.map(\.textContent) == ["name", "cpu"])
        #expect(table.body.map { $0.props["key"]?.string } == ["a", "1"])
        #expect(table.body.last?.children.map(\.textContent) == ["y", "7%"])
        #expect(table.body.last?.children.last?.props["align"] == .string("right"))
    }

    @Test func barChartGetsLabelAndValueSlotsPerBar() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: Self.dashboard, data: ["load": 1])
        let chart = try #require(page.node("BarChart"))
        #expect(chart.props["max"] == .number(4))
        #expect(chart.props["height"] == .number(160))
        #expect(chart.props["data"] == .array([.object(["value": .number(2)]),
                                               .object(["value": .number(4), "color": .string("red")])]))
        #expect(chart.slot("label1")?.first?.textContent == "b")
        #expect(chart.slot("value1")?.first?.textContent == "4!")
        #expect(page.node("Grid")?.props["columns"] == .string("max-content 1fr"))
        #expect(page.node("Text")?.props["weight"] == .number(600))
    }

    @Test func buttonsAddAFooterAtTheRoot() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(markdown: "Hi")
        #expect(page.node("Footer") == nil)
        _ = await page.render(["kind": "markdown", "source": "Hi", "wait": true, "buttons": ["Approve", "", "Reject"]])
        let footer = try #require(page.tree.root.children.last)
        #expect(footer.type == "Footer")
        #expect(footer.props["buttons"] == .array([.string("Approve"), .string("Reject")]))
        #expect(footer.props["wait"] == .bool(true))
        #expect(page.tree.root.children.map(\.type) == ["Markdown", "Footer"])
    }

    @Test func aSecondRenderReplacesTheFirst() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        _ = await page.render(tsx: Self.dashboard, data: ["load": 1])
        _ = await page.render(markdown: "# Two")
        #expect(page.tree.root.children.map(\.type) == ["Markdown"])
        #expect(page.nodes("Card").isEmpty)
        #expect(page.tree.count == 1)
    }

    @Test func compileErrorsComeBackWithACodeFrame() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        let result = await page.render(tsx: "export default function App() { return <Text> }")
        #expect(result.error?.hasPrefix("Syntax error") == true)
        #expect(result.stack?.contains("^") == true)
        #expect(!result.needsWeb)
    }

    @Test func importsOutsideReactAndCanvasAreRejected() async throws {
        let page = try NativeHarness()
        defer { page.close() }
        let result = await page.render(tsx: "import fs from 'fs'\nexport default function App() { return fs.x }")
        #expect(result.error?.contains("Cannot import 'fs'") == true)
    }
}
