import CanvasCore
import SwiftUI

struct BarChartView: View {
    @ObservedObject var node: ViewNode
    @Environment(\.kitTheme) private var theme

    var body: some View {
        let data = node.prop("data")?.array ?? []
        let values = data.map { max(0, KitValue.number($0["value"]) ?? 0) }
        let top = KitValue.number(node.prop("max")) ?? values.max() ?? 0
        let fallback = theme.resolve(node.prop("color")?.string)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(data.indices), id: \.self) { index in
                BarColumn(node: node, index: index, value: values[index], ratio: top > 0 ? values[index] / top : 0,
                          color: theme.resolve(data[index]["color"]?.string, fallback: fallback))
            }
        }
        .frame(height: KitValue.length(node.prop("height")) ?? 160)
        .frame(maxWidth: .infinity)
    }
}

private struct BarColumn: View {
    @ObservedObject var node: ViewNode
    let index: Int
    let value: Double
    let ratio: Double
    let color: RGBA

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 2, bottomTrailingRadius: 2,
                                       topTrailingRadius: 5)
                    .fill(Color(color).opacity(0.82))
                    .frame(maxWidth: 36)
                    .frame(height: max(2, ratio * max(0, geometry.size.height - 16)))
                    .overlay(alignment: .top) {
                        label("value", fallback: NumberText.format(value), style: Self.valueStyle)
                            .fixedSize()
                            .alignmentGuide(.top) { $0[.bottom] + 5 }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            label("label", fallback: "", style: TextStyle(size: 11.5, ink: .subtle, lineHeight: 1))
        }
        .frame(maxWidth: .infinity)
    }

    static let valueStyle = TextStyle(size: 11, weight: .medium, ink: .muted, lineHeight: 1, tabular: true)

    /// The `label<i>` or `value<i>` slot, else `fallback`.
    @ViewBuilder
    private func label(_ name: String, fallback: String, style: TextStyle) -> some View {
        Group {
            if let slot = node.slotNode("\(name)\(index)") {
                SlotFlow(slot: slot)
            } else {
                InlineLabel(text: fallback)
            }
        }
        .kitText { $0 = style }
        .lineLimit(1)
    }
}

/// A plain string in the inherited text style.
struct InlineLabel: View {
    let text: String
    @Environment(\.kitText) private var style

    var body: some View { Text(text).textLayout(style) }
}

/// Sparkline points: x as a fraction of the width, y in points with 3 pt
/// padding, as the web's SVG polyline.
struct SparkGeometry: Equatable {
    let points: [CGPoint]
    let height: CGFloat

    init(_ data: [Double], height: CGFloat) {
        self.height = height
        guard let low = data.min(), let high = data.max() else {
            points = []
            return
        }
        let span = high - low == 0 ? 1 : high - low
        let pad: CGFloat = 3
        points = data.enumerated().map { index, value in
            CGPoint(x: data.count == 1 ? 0.5 : CGFloat(index) / CGFloat(data.count - 1),
                    y: pad + CGFloat(1 - (value - low) / span) * (height - pad * 2))
        }
    }

    func line(width: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.x * width, y: $0.y) })
        return path
    }

    func area(width: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: 0, y: height)] + points.map { CGPoint(x: $0.x * width, y: $0.y) }
            + [CGPoint(x: width, y: height)])
        path.closeSubpath()
        return path
    }
}

struct SparklineView: View {
    @ObservedObject var node: ViewNode
    @Environment(\.kitTheme) private var theme

    var body: some View {
        let height = KitValue.length(node.prop("height")) ?? 32
        let geometry = SparkGeometry((node.prop("data")?.array ?? []).compactMap(KitValue.number), height: height)
        let width = node.prop("width")
        let full = width?.string?.hasSuffix("%") == true
        SparkShape(geometry: geometry, color: theme.resolve(node.prop("color")?.string),
                   fill: node.prop("fill").map(\.isTrue) ?? true, ring: theme.tokens.card)
            .frame(width: full ? nil : KitValue.length(width) ?? 120, height: height)
            .frame(maxWidth: full ? .infinity : nil)
    }
}

private struct SparkShape: View {
    let geometry: SparkGeometry
    let color: RGBA
    let fill: Bool
    let ring: RGBA

    var body: some View {
        Canvas { context, size in
            guard let last = geometry.points.last else { return }
            if fill { context.fill(Path(geometry.area(width: size.width)), with: .color(Color(color).opacity(0.12))) }
            context.stroke(Path(geometry.line(width: size.width)), with: .color(Color(color)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            let dot = CGPoint(x: last.x * size.width, y: last.y)
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 4.5, y: dot.y - 4.5, width: 9, height: 9)),
                         with: .color(Color(ring)))
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 2.5, y: dot.y - 2.5, width: 5, height: 5)),
                         with: .color(Color(color)))
        }
    }
}
