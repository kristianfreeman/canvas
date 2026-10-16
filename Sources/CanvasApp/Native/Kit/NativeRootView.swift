import CanvasCore
import SwiftUI

/// What a native panel draws: its tree's root, title and theme, plus where
/// its events go. The panel owns one and changes `title` and `theme` in place.
final class NativeSurface: ObservableObject {
    let root: ViewNode
    let fields = FieldStore()
    @Published var title: String
    @Published var theme: Theme
    weak var events: NativeEvents?
    /// Written during layout and read right after it, so not published.
    let laidOut = LaidOutHeights()

    init(root: ViewNode, title: String = "", theme: Theme = Theme(mode: .dark)) {
        self.root = root
        self.title = title
        self.theme = theme
    }
}

/// The scrolling panel's content and viewport heights from its last layout.
final class LaidOutHeights {
    var content: CGFloat = 0
    var viewport: CGFloat = 0
}

/// The content area: the root's children (except the footer) with the
/// web's `.cv-content` padding, 6 pt on top and 24 pt elsewhere.
struct NativeRootView: View {
    static let padding = EdgeInsets(top: 6, leading: 24, bottom: 24, trailing: 24)

    @ObservedObject var root: ViewNode

    var body: some View {
        BlockFlow(nodes: root.children.filter { $0.type != NativeFooter.type })
            .kitText { $0 = .body }
            .padding(Self.padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// The footer the runtime appends to the root when the request has `buttons`.
struct NativeFooter: View {
    static let type = "Footer"

    @ObservedObject var root: ViewNode

    var body: some View {
        if let footer = root.children.last(where: { $0.type == Self.type }) {
            FooterView(node: footer)
        }
    }
}

/// A whole native panel: header, content and footer on the theme's
/// background. `scrolls` is false for measuring and snapshots, where the
/// content takes its full height.
struct NativePanelView: View {
    @ObservedObject var surface: NativeSurface
    var scrolls = true
    var controls = ControlRendering.live

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: surface.title) { surface.events?.close() }
            if scrolls {
                scrollingContent
            } else {
                NativeRootView(root: surface.root)
            }
            NativeFooter(root: surface.root)
        }
        .background(Color(surface.theme.tokens.bg))
        .modifier(KitEnvironment(theme: surface.theme, events: EventsRef(target: surface.events),
                                 fields: surface.fields, controls: controls))
    }

    private var scrollingContent: some View {
        let laidOut = surface.laidOut
        return ScrollView(.vertical) {
            NativeRootView(root: surface.root)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { laidOut.content = $0 }
        }
        .frame(maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { laidOut.viewport = $0 }
    }
}

/// Theme, events, fields and link handling for everything under a panel.
/// It takes values, not the surface, so a theme change is a changed input.
struct KitEnvironment: ViewModifier {
    let theme: Theme
    let events: EventsRef
    let fields: FieldStore
    let controls: ControlRendering

    func body(content: Content) -> some View {
        content
            .environment(\.kitTheme, theme)
            .environment(\.kitEvents, events)
            .environment(\.kitFields, fields)
            .environment(\.kitControls, controls)
            .environment(\.colorScheme, theme.mode == .dark ? .dark : .light)
            .environment(\.openURL, OpenURLAction { url in
                LinkPolicy.open(url, with: events.target)
                return .handled
            })
            .tint(Color(theme.accent))
    }
}
