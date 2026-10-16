import CanvasCore
import SwiftUI

private struct FillsHeightKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set for grid items, which CSS grid stretches to the row's height.
    var kitFillsHeight: Bool {
        get { self[FillsHeightKey.self] }
        set { self[FillsHeightKey.self] = newValue }
    }
}

/// Children of a flex or grid container: text runs and element items.
struct FlexItems: View {
    let nodes: [ViewNode]

    var body: some View {
        ForEach(Flow.segments(nodes, inline: Flow.textOnly)) { SegmentView(segment: $0) }
    }
}

struct StackView: View {
    @ObservedObject var node: ViewNode

    var body: some View {
        let gap = KitValue.length(node.prop("gap")) ?? 12
        VStack(alignment: Self.alignment(node.prop("align")?.string), spacing: gap) {
            FlexItems(nodes: node.body)
        }
        .environment(\.kitFillsHeight, false)
    }

    static func alignment(_ align: String?) -> HorizontalAlignment {
        switch align {
        case "center": .center
        case "end": .trailing
        default: .leading
        }
    }
}

struct RowView: View {
    @ObservedObject var node: ViewNode

    var body: some View {
        let gap = KitValue.length(node.prop("gap")) ?? 12
        let align = Self.alignment(node.prop("align")?.string)
        if node.prop("wrap")?.isTrue == true {
            FlowLayout(spacing: gap, alignment: align) { FlexItems(nodes: node.body) }
        } else {
            HStack(alignment: align, spacing: 0) {
                JustifiedItems(segments: Flow.segments(node.body, inline: Flow.textOnly),
                               justify: Justify(node.prop("justify")?.string), gap: gap)
            }
            .environment(\.kitFillsHeight, false)
        }
    }

    static func alignment(_ align: String?) -> VerticalAlignment {
        switch align {
        case "start": .top
        case "end": .bottom
        case "baseline": .firstTextBaseline
        default: .center
        }
    }
}

enum Justify {
    case start, center, end, between, around

    init(_ value: String?) {
        switch value {
        case "center": self = .center
        case "end": self = .end
        case "between": self = .between
        case "around", "evenly": self = .around
        default: self = .start
        }
    }

    var leads: Bool { self == .center || self == .end || self == .around }
    var trails: Bool { self == .center || self == .around }
    var spreads: Bool { self == .between || self == .around }
}

/// Row items with `gap` between them, and spacers for `justify`.
struct JustifiedItems: View {
    let segments: [FlowSegment]
    let justify: Justify
    let gap: CGFloat

    var body: some View {
        if justify.leads { Spacer(minLength: 0) }
        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
            if index > 0 {
                if justify.spreads { Spacer(minLength: gap) } else { Color.clear.frame(width: gap, height: 0) }
            }
            SegmentView(segment: segment)
        }
        if justify.trails { Spacer(minLength: 0) }
    }
}

struct GridView: View {
    @ObservedObject var node: ViewNode

    var body: some View {
        TrackGridLayout(tracks: GridTracks.parse(node.prop("columns")), gap: KitValue.length(node.prop("gap")) ?? 12) {
            ForEach(Flow.segments(node.body, inline: Flow.textOnly)) { segment in
                SegmentView(segment: segment).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .environment(\.kitFillsHeight, true)
    }
}

struct DividerView: View {
    @Environment(\.kitTheme) private var theme

    var body: some View {
        Rectangle().fill(Color(theme.tokens.border)).frame(maxWidth: .infinity).frame(height: 1).padding(.vertical, 4)
    }
}

struct SpacerView: View {
    @ObservedObject var node: ViewNode

    var body: some View {
        if let size = KitValue.length(node.prop("size")) {
            Color.clear.frame(width: size, height: size)
        } else {
            Spacer(minLength: 0)
        }
    }
}
