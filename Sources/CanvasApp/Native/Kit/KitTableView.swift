import CanvasCore
import Combine
import SwiftUI

/// `Table` columns: count, alignment and fixed widths from the `columns`
/// prop, or the widest row when there is none.
struct TableSpec: Equatable {
    let aligns: [TextAlign?]
    let widths: [CGFloat?]

    var count: Int { aligns.count }

    init(_ table: ViewNode) {
        let columns = table.prop("columns")?.array ?? []
        if columns.isEmpty {
            let rows = [table.slotNode("head")].compactMap { $0 } + table.body
            let count = max(1, rows.map { $0.children.count }.max() ?? 1)
            aligns = Array(repeating: nil, count: count)
            widths = Array(repeating: nil, count: count)
        } else {
            aligns = columns.map { KitValue.align($0["align"]) }
            widths = columns.map { KitValue.length($0["width"]) }
        }
    }
}

/// A head cell's `sort`.
enum SortDirection: String {
    case ascending, descending

    var arrow: String { self == .descending ? "↓" : "↑" }

    /// The sorted column's direction, if any head cell has one.
    static func of(_ cells: [ViewNode]) -> Self? {
        cells.lazy.compactMap { $0.prop("sort")?.string.flatMap(Self.init) }.first
    }
}

struct TableView: View {
    @ObservedObject var node: ViewNode
    @State private var revision = 0

    var body: some View {
        _ = revision
        let spec = TableSpec(node)
        let head = node.slotNode("head")
        let headCells = head?.children ?? []
        let rows = node.body.filter { $0.type == "TableRow" }
        return TableLayout(fixed: spec.widths) {
            if let head {
                TableRowCells(row: head, spec: spec, header: true, lastRow: false, sort: SortDirection.of(headCells))
            }
            ForEach(rows, id: \.id) { row in
                TableRowCells(row: row, spec: spec, header: false, lastRow: row === rows.last)
            }
        }
        .kitText { $0.size = 13.5; $0.tabular = true }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(Publishers.MergeMany(headCells.map(\.objectWillChange))) { _ in revision &+= 1 }
    }
}

/// One row's cells, padded with empty cells to the column count. A row
/// with `onClick` is clickable as a whole and lights up on hover; a
/// `selected` row is tinted with the accent.
private struct TableRowCells: View {
    @ObservedObject var row: ViewNode
    let spec: TableSpec
    let header: Bool
    let lastRow: Bool
    var sort: SortDirection?
    @Environment(\.kitTheme) private var theme
    @Environment(\.kitEvents) private var events
    @State private var hovering = false

    var body: some View {
        let cells = row.children.filter { $0.type == "TableCell" }
        let clickable = !header && row.prop("onClick")?.function != nil
        let fill = TableRowFill.fill(theme: theme, hovered: clickable && hovering,
                                     selected: row.prop("selected")?.isTrue == true)
        ForEach(Array(0..<spec.count), id: \.self) { column in
            cell(column, cells: cells, fill: fill)
                .modifier(RowClick(enabled: clickable, hovering: $hovering) {
                    KitActions(events: events.target, fields: nil).click(row)
                })
        }
    }

    @ViewBuilder
    private func cell(_ column: Int, cells: [ViewNode], fill: RGBA?) -> some View {
        let position = CellPosition(column: column, columns: spec.count, header: header, lastRow: lastRow)
        if column >= cells.count {
            TableCellChrome(position: position, align: nil, fill: fill) { Color.clear.frame(width: 0, height: 0) }
        } else if header {
            HeadCellView(cell: cells[column], position: position, columnAlign: spec.aligns[column], sort: sort)
        } else {
            TableCellView(cell: cells[column], position: position, columnAlign: spec.aligns[column], fill: fill)
        }
    }
}

enum TableRowFill {
    /// Hover wins over selection, as in styles.css.
    static func fill(theme: Theme, hovered: Bool, selected: Bool) -> RGBA? {
        if hovered { return theme.tokens.cardHover }
        return selected ? theme.accent.opacity(0.12) : nil
    }
}

private struct RowClick: ViewModifier {
    let enabled: Bool
    @Binding var hovering: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.contentShape(Rectangle()).onTapGesture(perform: action).onHover { hovering = $0 }
        } else {
            content
        }
    }
}

private struct TableCellView: View {
    @ObservedObject var cell: ViewNode
    let position: CellPosition
    let columnAlign: TextAlign?
    let fill: RGBA?

    var body: some View {
        TableCellChrome(position: position, align: KitValue.align(cell.prop("align")) ?? columnAlign, fill: fill) {
            BlockFlow(nodes: cell.children)
        }
    }
}

/// A header: its label, then 4 pt and the sort arrow. While the table is
/// sorted every header holds the arrow, hidden on the unsorted ones, so
/// widths don't jump when the sort moves. With `onClick` it's a plain
/// button whose text turns `fg` on hover and when sorted.
private struct HeadCellView: View {
    @ObservedObject var cell: ViewNode
    let position: CellPosition
    let columnAlign: TextAlign?
    let sort: SortDirection?
    @Environment(\.kitEvents) private var events
    @State private var hovering = false

    var body: some View {
        let sorted = cell.prop("sort")?.string.flatMap(SortDirection.init) != nil
        let clickable = cell.prop("onClick")?.function != nil
        let lit = clickable && (hovering || sorted)
        TableCellChrome(position: position, align: KitValue.align(cell.prop("align")) ?? columnAlign) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                BlockFlow(nodes: cell.children)
                if let sort { InlineLabel(text: sort.arrow).opacity(sorted ? 1 : 0) }
            }
            .kitText { $0 = TableCellChrome<EmptyView>.headerStyle($0).with { if lit { $0.ink = .fg } } }
            .fixedSize(horizontal: true, vertical: false)
            .modifier(RowClick(enabled: clickable, hovering: $hovering) {
                KitActions(events: events.target, fields: nil).click(cell)
            })
        }
    }
}
