import CanvasCore
import SwiftUI

/// How controls draw. `ImageRenderer` can't capture AppKit-backed controls
/// (text fields, menus, scroll views), so snapshots draw them as static views.
enum ControlRendering {
    case live
    case still
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(mode: .dark)
}

private struct EventsKey: EnvironmentKey {
    static let defaultValue = EventsRef()
}

private struct TextStyleKey: EnvironmentKey {
    static let defaultValue = TextStyle.body
}

private struct FieldsKey: EnvironmentKey {
    static let defaultValue: FieldStore? = nil
}

private struct ControlsKey: EnvironmentKey {
    static let defaultValue = ControlRendering.live
}

extension EnvironmentValues {
    var kitTheme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }

    var kitEvents: EventsRef {
        get { self[EventsKey.self] }
        set { self[EventsKey.self] = newValue }
    }

    /// The text style bare text and inline runs take, like CSS inheritance.
    var kitText: TextStyle {
        get { self[TextStyleKey.self] }
        set { self[TextStyleKey.self] = newValue }
    }

    var kitFields: FieldStore? {
        get { self[FieldsKey.self] }
        set { self[FieldsKey.self] = newValue }
    }

    var kitControls: ControlRendering {
        get { self[ControlsKey.self] }
        set { self[ControlsKey.self] = newValue }
    }
}

extension Color {
    init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

extension View {
    /// Applies `change` to the inherited text style for this subtree.
    func kitText(_ change: @escaping (inout TextStyle) -> Void) -> some View {
        transformEnvironment(\.kitText, transform: change)
    }
}
