import CanvasCore
import SwiftUI

/// The panel header: 40 pt, the title in muted 13 pt at the left, and the
/// × in the rightmost 44 pt, which the native drag strip leaves free.
struct PanelHeader: View {
    static let height: CGFloat = 40
    static let closeWidth: CGFloat = 44

    let title: String
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(title)
                .textLayout(TextStyle(size: 13, weight: .medium, ink: .muted, lineHeight: 1.3, tracking: 0.005))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 16)
                .padding(.trailing, 52)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) { CloseIcon().stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round)) }
                .buttonStyle(CloseButtonStyle())
                .frame(width: Self.closeWidth, height: Self.height, alignment: .trailing)
                .accessibilityLabel("Close")
        }
        .frame(height: Self.height)
    }
}

private struct CloseIcon: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
    }
}

/// `.cv-close`: a 40 pt square whose inner 24 pt rounds in on hover.
private struct CloseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CloseButtonBody(configuration: configuration)
    }
}

private struct CloseButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.kitTheme) private var theme
    @State private var hovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(Color(hovering ? theme.tokens.cardHover : .clear)).padding(8)
            configuration.label
                .foregroundColor(Color(hovering ? theme.tokens.fg : theme.tokens.fgSubtle))
                .frame(width: 7, height: 7)
        }
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
