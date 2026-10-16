import AppKit

/// The macOS accent color as a CSS hex color.
enum Accent {
    static func hex(in appearance: NSAppearance) -> String {
        var hex = "#0a84ff"
        appearance.performAsCurrentDrawingAppearance {
            guard let rgb = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return }
            hex = "#" + [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
                .map { String(format: "%02x", Int((min(max($0, 0), 1) * 255).rounded())) }
                .joined()
        }
        return hex
    }
}
