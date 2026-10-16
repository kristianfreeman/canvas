import CanvasCore
import SwiftUI

/// One column track of `Grid.columns`.
enum GridTrack: Equatable {
    case fixed(CGFloat)
    case fraction(CGFloat)
    /// `max-content` or `auto` (true), `min-content` (false).
    case content(max: Bool)

    var fraction: CGFloat {
        if case .fraction(let share) = self { return share }
        return 0
    }
}

enum GridTracks {
    /// A number n is n equal columns; a string is CSS track sizes, with
    /// `repeat()` and `minmax()`. Anything unreadable is one `1fr`.
    static func parse(_ value: JSONValue?) -> [GridTrack] {
        if let count = value?.number, count.isFinite, count >= 1 {
            return Array(repeating: .fraction(1), count: Int(min(count, 64)))
        }
        let tracks = value?.string.map { tokens($0).flatMap(expand) } ?? []
        return tracks.isEmpty ? [.fraction(1), .fraction(1)] : Array(tracks.prefix(64))
    }

    /// Splits on whitespace outside parentheses.
    static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var depth = 0
        for char in text {
            if char == "(" { depth += 1 } else if char == ")" { depth -= 1 }
            if char.isWhitespace && depth == 0 {
                if !current.isEmpty { tokens.append(current) }
                current = ""
            } else {
                current.append(char)
            }
        }
        return current.isEmpty ? tokens : tokens + [current]
    }

    private static func expand(_ token: String) -> [GridTrack] {
        guard token.hasPrefix("repeat("), token.hasSuffix(")") else { return [track(token)] }
        let inner = token.dropFirst(7).dropLast()
        guard let comma = inner.firstIndex(of: ","),
              let count = Int(inner[..<comma].trimmingCharacters(in: .whitespaces)), count > 0 else { return [] }
        let pattern = tokens(String(inner[inner.index(after: comma)...])).map(track)
        return Array(repeating: pattern, count: min(count, 64)).flatMap { $0 }
    }

    static func track(_ token: String) -> GridTrack {
        if token.hasPrefix("minmax("), token.hasSuffix(")"), let comma = token.lastIndex(of: ",") {
            return track(token[token.index(after: comma)...].dropLast().trimmingCharacters(in: .whitespaces))
        }
        switch token {
        case "max-content", "auto": return .content(max: true)
        case "min-content": return .content(max: false)
        default: break
        }
        if token.hasSuffix("fr"), let value = Double(token.dropLast(2)), value.isFinite, value >= 0 {
            return .fraction(CGFloat(value))
        }
        return KitValue.length(.string(token)).map(GridTrack.fixed) ?? .fraction(1)
    }
}

/// CSS grid with explicit column tracks, auto rows, items placed in order
/// one per cell and stretched to their cell.
struct TrackGridLayout: Layout {
    let tracks: [GridTrack]
    let gap: CGFloat

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
            let column = index % tracks.count
            let row = index / tracks.count
            subview.place(at: CGPoint(x: bounds.minX + solved.columnX[column], y: bounds.minY + solved.rowY[row]),
                          proposal: ProposedViewSize(width: solved.columns[column], height: solved.rows[row]))
        }
    }

    func solve(width: CGFloat?, subviews: Subviews) -> TrackSolution {
        let columns = TrackSizing(tracks: tracks, gap: gap).widths(available: width) { column, proposal in
            stride(from: column, to: subviews.count, by: tracks.count)
                .map { subviews[$0].sizeThatFits(proposal).width }.max() ?? 0
        }
        let rowCount = (subviews.count + tracks.count - 1) / tracks.count
        let rows = (0..<rowCount).map { row in
            (0..<tracks.count).compactMap { column -> CGFloat? in
                let index = row * tracks.count + column
                guard index < subviews.count else { return nil }
                return subviews[index].sizeThatFits(ProposedViewSize(width: columns[column], height: nil)).height
            }.max() ?? 0
        }
        return TrackSolution(columns: columns, rows: rows, gap: gap)
    }
}

struct TrackSolution {
    let columns: [CGFloat]
    let rows: [CGFloat]
    let columnX: [CGFloat]
    let rowY: [CGFloat]
    let width: CGFloat
    let height: CGFloat

    init(columns: [CGFloat], rows: [CGFloat], gap: CGFloat) {
        self.columns = columns
        self.rows = rows
        columnX = Self.offsets(columns, gap: gap)
        rowY = Self.offsets(rows, gap: gap)
        width = columns.reduce(0, +) + gap * CGFloat(max(columns.count - 1, 0))
        height = rows.reduce(0, +) + gap * CGFloat(max(rows.count - 1, 0))
    }

    static func offsets(_ sizes: [CGFloat], gap: CGFloat) -> [CGFloat] {
        sizes.indices.map { index in sizes[..<index].reduce(0, +) + gap * CGFloat(index) }
    }
}

/// Column widths for grid tracks: fixed tracks first, then content tracks
/// at their items' widths, then `fr` tracks share what's left.
struct TrackSizing {
    let tracks: [GridTrack]
    let gap: CGFloat

    /// `measure(column, proposal)` is the widest item in a column.
    func widths(available: CGFloat?, measure: (Int, ProposedViewSize) -> CGFloat) -> [CGFloat] {
        var widths = tracks.enumerated().map { column, track -> CGFloat in
            switch track {
            case .fixed(let width): width
            case .content(let max): measure(column, max ? .unspecified : ProposedViewSize(width: 0, height: nil))
            case .fraction: 0
            }
        }
        let fractions = tracks.map(\.fraction)
        let total = fractions.reduce(0, +)
        guard total > 0 else { return widths }
        let unit = available.map { width in
            max(0, width - widths.reduce(0, +) - gap * CGFloat(tracks.count - 1)) / total
        } ?? idealUnit(fractions) { measure($0, .unspecified) }
        for (column, share) in fractions.enumerated() where share > 0 { widths[column] = share * unit }
        return widths
    }

    /// Without a width, an `fr` is as wide as the widest item needs.
    private func idealUnit(_ fractions: [CGFloat], measure: (Int) -> CGFloat) -> CGFloat {
        fractions.enumerated().filter { $0.element > 0 }.map { measure($0.offset) / $0.element }.max() ?? 0
    }
}
