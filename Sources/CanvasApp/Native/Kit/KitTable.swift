import CanvasCore
import SwiftUI

/// Where a cell sits, which decides its padding and bottom border.
struct CellPosition: Equatable {
    let column: Int
    let columns: Int
    let header: Bool
    let lastRow: Bool
}

/// The web's table cell: 9 × 14 padding (none on the outer edges), a
/// bottom border except on the last row, header text muted and unwrapped.
struct TableCellChrome<Content: View>: View {
    let position: CellPosition
    let align: TextAlign?
    /// A selected or hovered row's cell background.
    var fill: RGBA?
    @ViewBuilder let content: Content
    @Environment(\.kitTheme) private var theme

    var body: some View {
        let edge: CGFloat = 14
        content
            .lineLimit(position.header ? 1 : nil)
            .padding(EdgeInsets(top: position.header ? 0 : 9, leading: position.column == 0 ? 0 : edge,
                                bottom: 9, trailing: position.column == position.columns - 1 ? 0 : edge))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: (align ?? .left).frame)
            .background(Color(fill ?? .clear))
            .multilineTextAlignment((align ?? .left).multiline)
            .overlay(alignment: .bottom) {
                if !position.lastRow {
                    Rectangle().fill(Color(position.header ? theme.tokens.borderStrong : theme.tokens.border))
                        .frame(height: 1)
                }
            }
    }

    /// `th`: 12 pt, medium, muted.
    static func headerStyle(_ base: TextStyle) -> TextStyle {
        base.with { $0.size = 12; $0.weight = .medium; $0.ink = .muted; $0.tracking = 0.01 }
    }
}

/// Table columns: header and body cells in row-major order, columns as
/// wide as their content (the CSS auto table layout), filling the width.
struct TableLayout: Layout {
    let fixed: [CGFloat?]

    func makeCache(subviews _: Subviews) -> SolutionCache { SolutionCache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout SolutionCache) -> CGSize {
        let solved = cache.solution(width: proposal.width) { solve(width: $0, subviews: subviews) }
        return CGSize(width: solved.width, height: solved.height)
    }

    // swiftlint:disable:next function_parameter_count - the Layout protocol fixes this signature
    func placeSubviews(in bounds: CGRect,
                       proposal _: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout SolutionCache) {
        let solved = cache.solution(width: bounds.width) { solve(width: $0, subviews: subviews) }
        for (index, subview) in subviews.enumerated() {
            let column = index % fixed.count
            let row = index / fixed.count
            subview.place(at: CGPoint(x: bounds.minX + solved.columnX[column], y: bounds.minY + solved.rowY[row]),
                          proposal: ProposedViewSize(width: solved.columns[column], height: solved.rows[row]))
        }
    }

    func solve(width: CGFloat?, subviews: Subviews) -> TrackSolution {
        let count = fixed.count
        let cells = { (column: Int) in stride(from: column, to: subviews.count, by: count).map { subviews[$0] } }
        let widest = (0..<count).map { cells($0).map { $0.sizeThatFits(.unspecified).width }.max() ?? 0 }
        let sizing = TableSizing(fixed: fixed, widest: widest) { column in
            cells(column).map { $0.sizeThatFits(.zeroWidth).width }.max() ?? 0
        }
        let columns = sizing.widths(available: width)
        let rows = stride(from: 0, to: subviews.count, by: count).map { start in
            (start..<min(start + count, subviews.count)).map { index in
                subviews[index].sizeThatFits(ProposedViewSize(width: columns[index - start], height: nil)).height
            }.max() ?? 0
        }
        return TrackSolution(columns: columns, rows: rows, gap: 0)
    }
}

/// Solutions for one layout pass, by proposed width. SwiftUI rebuilds the
/// cache whenever the container or its subviews change.
struct SolutionCache {
    private var solutions: [CGFloat?: TrackSolution] = [:]

    mutating func solution(width: CGFloat?, solve: (CGFloat?) -> TrackSolution) -> TrackSolution {
        if let cached = solutions[width] { return cached }
        let solved = solve(width)
        solutions[width] = solved
        return solved
    }
}

extension ProposedViewSize {
    static let zeroWidth = Self(width: 0, height: nil)
}

/// Auto table layout: extra width goes to columns in proportion to their
/// content, and a short width shrinks them toward their narrowest.
struct TableSizing {
    let fixed: [CGFloat?]
    let widest: [CGFloat]
    /// A column's narrowest width, measured only when the table must shrink.
    let narrowest: (Int) -> CGFloat

    init(fixed: [CGFloat?], widest: [CGFloat], narrowest: @escaping (Int) -> CGFloat) {
        self.fixed = fixed
        self.widest = widest
        self.narrowest = narrowest
    }

    init(fixed: [CGFloat?], widest: [CGFloat], narrowest: [CGFloat]) {
        self.init(fixed: fixed, widest: widest) { narrowest[$0] }
    }

    func widths(available: CGFloat?) -> [CGFloat] {
        let natural = fixed.indices.map { fixed[$0] ?? widest[$0] }
        guard let available else { return natural }
        let free = fixed.indices.filter { fixed[$0] == nil }
        let flexible = free.map { widest[$0] }.reduce(0, +)
        let spare = available - natural.reduce(0, +)
        if spare >= 0 {
            return natural.indices.map { index in
                guard fixed[index] == nil else { return natural[index] }
                return natural[index] + (flexible > 0 ? spare * widest[index] / flexible : spare / CGFloat(free.count))
            }
        }
        return shrunk(natural: natural, deficit: -spare)
    }

    private func shrunk(natural: [CGFloat], deficit: CGFloat) -> [CGFloat] {
        let room = fixed.indices.map { fixed[$0] == nil ? max(0, widest[$0] - min(narrowest($0), widest[$0])) : 0 }
        let total = room.reduce(0, +)
        guard total > 0 else { return natural }
        let share = min(1, deficit / total)
        return natural.indices.map { natural[$0] - room[$0] * share }
    }
}
