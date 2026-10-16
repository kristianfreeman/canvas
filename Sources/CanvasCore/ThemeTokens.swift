import Foundation

public enum ThemeMode: String, Equatable, CaseIterable {
    case dark
    case light
}

/// Apple's system colors, which styles.css defines as `--<name>`.
public enum Hue: String, CaseIterable {
    case red, orange, yellow, green, teal, blue, purple, pink, gray
}

/// The semantic tokens from web/src/styles.css for one theme.
public struct ThemeTokens: Equatable {
    public let bg, fg, fgSoft, fgMuted, fgSubtle: RGBA
    public let surface, surfaceRaised: RGBA
    public let border, borderStrong, borderHover: RGBA
    public let card, cardHover, field: RGBA
    public let codeBg, inlineCodeBg: RGBA
    public let kbdBg, kbdBorder, kbdEdge: RGBA
    public let track: RGBA
    /// How much of a hue tinted text keeps when mixed toward `fg` (`--ink`).
    public let ink: Double
    /// `--warning`: yellow in dark, orange in light.
    public let warningHue: Hue
    let hues: [Hue: RGBA]

    public func hue(_ hue: Hue) -> RGBA { hues[hue] ?? fg }

    public static let dark = Self(
        bg: hex("#0a0a0a"), fg: hex("#ededed"), fgSoft: hex("#c9c9c9"), fgMuted: hex("#a1a1a1"),
        fgSubtle: hex("#6e6e6e"), surface: hex("#141414"), surfaceRaised: hex("#1a1a1a"),
        border: RGBA.white.opacity(0.08), borderStrong: RGBA.white.opacity(0.13), borderHover: RGBA.white.opacity(0.2),
        card: hex("#121212"), cardHover: hex("#1c1c1c"), field: hex("#0f0f0f"),
        codeBg: hex("#111111"), inlineCodeBg: RGBA.white.opacity(0.07),
        kbdBg: hex("#181818"), kbdBorder: RGBA.white.opacity(0.1), kbdEdge: RGBA.white.opacity(0.16),
        track: RGBA.white.opacity(0.08), ink: 1, warningHue: .yellow,
        hues: hues(["#ff453a", "#ff9f0a", "#ffd60a", "#30d158", "#40c8e0", "#0a84ff", "#bf5af2", "#ff375f", "#98989d"])
    )

    public static let light = Self(
        bg: hex("#ffffff"), fg: hex("#171717"), fgSoft: hex("#3b3b3b"), fgMuted: hex("#6b6b6b"),
        fgSubtle: hex("#a3a3a3"), surface: hex("#f5f5f5"), surfaceRaised: hex("#ffffff"),
        border: RGBA.black.opacity(0.08), borderStrong: RGBA.black.opacity(0.13), borderHover: RGBA.black.opacity(0.22),
        card: hex("#fafafa"), cardHover: hex("#f0f0f0"), field: hex("#ffffff"),
        codeBg: hex("#f7f7f7"), inlineCodeBg: RGBA.black.opacity(0.05),
        kbdBg: hex("#ffffff"), kbdBorder: RGBA.black.opacity(0.12), kbdEdge: RGBA.black.opacity(0.2),
        track: RGBA.black.opacity(0.07), ink: 0.72, warningHue: .orange,
        hues: hues(["#ff3b30", "#ff9500", "#ffcc00", "#34c759", "#30b0c7", "#007aff", "#af52de", "#ff2d55", "#8e8e93"])
    )

    public static func of(_ mode: ThemeMode) -> Self { mode == .dark ? dark : light }

    private static func hex(_ text: String) -> RGBA { RGBA(hex: text) ?? .black }

    private static func hues(_ values: [String]) -> [Hue: RGBA] {
        Dictionary(uniqueKeysWithValues: zip(Hue.allCases, values.map(hex)))
    }
}
