import SwiftUI

/// A wrapping row (`Row wrap`): items left to right, onto a new line when
/// the next one doesn't fit.
struct FlowLayout: Layout {
    let spacing: CGFloat
    let alignment: VerticalAlignment

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout Void) -> CGSize {
        let lines = lines(width: proposal.width, subviews: subviews)
        let width = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height(of: lines))
    }

    // swiftlint:disable:next function_parameter_count - the Layout protocol fixes this signature
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout Void) {
        var top = bounds.minY
        for line in lines(width: bounds.width, subviews: subviews) {
            var left = bounds.minX
            for (index, size) in zip(line.indices, line.sizes) {
                let offset = alignment == .bottom ? line.height - size.height
                    : alignment == .center ? (line.height - size.height) / 2 : 0
                subviews[index].place(at: CGPoint(x: left, y: top + offset), proposal: ProposedViewSize(size))
                left += size.width + spacing
            }
            top += line.height + spacing
        }
    }

    struct Line {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat { sizes.map(\.height).max() ?? 0 }
    }

    func lines(width: CGFloat?, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            let next = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            if let width, next > width, !line.indices.isEmpty {
                lines.append(line)
                line = Line()
            }
            line.width = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            line.indices.append(index)
            line.sizes.append(size)
        }
        return line.indices.isEmpty ? lines : lines + [line]
    }

    private func height(of lines: [Line]) -> CGFloat {
        lines.map(\.height).reduce(0, +) + spacing * CGFloat(max(lines.count - 1, 0))
    }
}
