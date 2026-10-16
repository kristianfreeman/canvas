import CanvasCore
import SwiftUI

/// A Stat's delta line: the arrow for its tone, then the delta without its sign.
struct StatDelta: Equatable {
    enum Tone: String { case up, down, flat }

    enum Verdict { case good, bad, neutral }

    let text: String
    let tone: Tone
    /// Neutral when flat.
    let verdict: Verdict

    init?(_ props: [String: JSONValue]) {
        guard let delta = props["delta"], delta != .null else { return nil }
        let tone = props["tone"]?.string.flatMap(Tone.init) ?? Self.tone(delta)
        self.tone = tone
        let good = props["good"].map(\.isTrue) ?? (tone == .up)
        verdict = tone == .flat ? .neutral : good ? .good : .bad
        let arrow = tone == .up ? "▲" : tone == .down ? "▼" : ""
        text = "\(arrow) \(Self.unsigned(delta))"
    }

    static func tone(_ delta: JSONValue) -> Tone {
        if let number = delta.number { return number > 0 ? .up : number < 0 ? .down : .flat }
        let text = (delta.string ?? "").trimmingCharacters(in: .whitespaces)
        if ["+", "▲", "↑"].contains(where: text.hasPrefix) { return .up }
        return ["-", "−", "▼", "↓"].contains(where: text.hasPrefix) ? .down : .flat
    }

    static func unsigned(_ delta: JSONValue) -> String {
        if let number = delta.number { return NumberText.format(abs(number)) }
        let text = delta.string ?? ""
        guard let first = text.first, "+-−▲▼↑↓".contains(first) else { return text }
        return String(text.dropFirst().drop { $0.isWhitespace })
    }
}

/// `Number.prototype.toLocaleString()` in en-US: grouped, up to 3 decimals.
enum NumberText {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        return formatter
    }()

    static func format(_ number: Double) -> String {
        formatter.string(from: NSNumber(value: number)) ?? String(number)
    }
}

struct StatView: View {
    @ObservedObject var node: ViewNode
    @Environment(\.kitTheme) private var theme

    var body: some View {
        let valueInk = node.prop("color")?.string.map { Ink.custom(theme.resolve($0)) } ?? .fg
        VStack(alignment: .leading, spacing: 4) {
            if let label = node.slotNode("label") {
                SlotFlow(slot: label).kitText { $0 = TextStyle(size: 12, weight: .medium, ink: .muted) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let value = node.slotNode("value") {
                    SlotFlow(slot: value).kitText {
                        $0 = TextStyle(size: 24, weight: .semibold, ink: valueInk, lineHeight: 1.15, tracking: -0.02,
                                       tabular: true)
                    }
                }
                if let delta = StatDelta(node.props) { deltaText(delta) }
            }
            if let hint = node.slotNode("hint") {
                SlotFlow(slot: hint).kitText { $0 = TextStyle(size: 12, ink: .subtle) }
            }
            BlockFlow(nodes: node.body)
        }
    }

    private func deltaText(_ delta: StatDelta) -> some View {
        let ink: Ink = switch delta.verdict {
        case .good: .custom(theme.ink(theme.success))
        case .bad: .custom(theme.ink(theme.danger))
        case .neutral: .muted
        }
        return Text(delta.text).textLayout(TextStyle(size: 12, weight: .medium, ink: ink, tabular: true))
            .lineLimit(1).fixedSize()
    }
}

struct BadgeView: View {
    @ObservedObject var node: ViewNode
    @Environment(\.kitTheme) private var theme

    var body: some View {
        let color = theme.resolve(node.prop("color")?.string)
        HStack(spacing: 6) {
            if node.prop("dot")?.isTrue == true {
                Circle().fill(Color(color)).frame(width: 6, height: 6)
            }
            BlockFlow(nodes: node.children)
                .kitText { $0 = TextStyle(size: 11.5, weight: .medium, ink: .custom(theme.ink(color)), lineHeight: 1) }
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 21)
        .background(Capsule().fill(Color(color.opacity(0.12))))
        .overlay(Capsule().strokeBorder(Color(color.opacity(0.18)), lineWidth: 1))
    }
}

struct ProgressBarView: View {
    @ObservedObject var node: ViewNode
    @Environment(\.kitTheme) private var theme

    var body: some View {
        let ratio = min(max(KitValue.number(node.prop("value")) ?? 0, 0), 1)
        let label = node.slotNode("label")
        let showValue = node.prop("showValue")?.isTrue == true
        VStack(alignment: .leading, spacing: 7) {
            if label != nil || showValue {
                HStack(spacing: 12) {
                    if let label { SlotFlow(slot: label) }
                    Spacer(minLength: 0)
                    if showValue {
                        Text("\(Int((ratio * 100).rounded()))%")
                            .textLayout(TextStyle(size: 12.5, ink: .muted, tabular: true))
                    }
                }
                .kitText { $0 = TextStyle(size: 12.5, ink: .soft, tabular: true) }
            }
            Capsule().fill(Color(theme.tokens.track))
                .overlay(LeadingCapsule(share: ratio).fill(Color(theme.resolve(node.prop("color")?.string))))
                .clipShape(Capsule())
                .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A capsule over the leading `share` of its rect: a progress fill.
struct LeadingCapsule: Shape {
    let share: Double

    func path(in rect: CGRect) -> Path {
        Capsule().path(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width * share, height: rect.height))
    }
}
