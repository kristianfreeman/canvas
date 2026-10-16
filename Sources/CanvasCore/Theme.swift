import Foundation

/// One panel's resolved look: the tokens for its mode plus its accent.
public struct Theme: Equatable {
    public let mode: ThemeMode
    public let tokens: ThemeTokens
    public let accent: RGBA
    /// `--accent-fg`: white on the default accent, else by contrast.
    public let accentForeground: RGBA

    /// `accent` is any CSS color the panel was given; nil or invalid uses
    /// the theme's blue, as the page does without `setAccent`.
    public init(mode: ThemeMode, accent: String? = nil) {
        let tokens = ThemeTokens.of(mode)
        self.mode = mode
        self.tokens = tokens
        if let given = accent.flatMap(CSSColor.parse) {
            self.accent = given
            accentForeground = given.contrastForeground
        } else {
            self.accent = tokens.hue(.blue)
            accentForeground = .white
        }
    }

    public static let semanticNames = ["accent", "success", "warning", "danger", "info", "muted"]

    /// A `color` prop: a semantic name, a hue name or a CSS color. Missing,
    /// empty and unparseable values give `fallback`.
    public func resolve(_ color: String?, fallback: RGBA) -> RGBA {
        guard let name = color?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return fallback }
        return semantic(name) ?? Hue(rawValue: name).map(tokens.hue) ?? CSSColor.parse(name) ?? fallback
    }

    /// `resolve` with the accent as the fallback, as the kit's `resolveColor`.
    public func resolve(_ color: String?) -> RGBA { resolve(color, fallback: accent) }

    /// Tinted text (badges, deltas): the hue mixed toward `fg` by `--ink`.
    public func ink(_ color: RGBA) -> RGBA { color.mixed(tokens.ink, with: tokens.fg) }

    public var success: RGBA { tokens.hue(.green) }
    public var warning: RGBA { tokens.hue(tokens.warningHue) }
    public var danger: RGBA { tokens.hue(.red) }
    public var info: RGBA { tokens.hue(.blue) }

    /// `--accent-hover`: the accent mixed toward white in dark, black in light.
    public var accentHover: RGBA {
        mode == .dark ? accent.mixed(0.84, with: .white) : accent.mixed(0.86, with: .black)
    }

    public var focusRing: RGBA { accent.opacity(0.38) }

    public var highlight: HighlightPalette { mode == .dark ? .githubDark : .githubLight }

    private static let semantic: [String: KeyPath<Self, RGBA>] = [
        "accent": \.accent, "success": \.success, "warning": \.warning, "danger": \.danger, "info": \.info,
        "muted": \.tokens.fgMuted
    ]

    private func semantic(_ name: String) -> RGBA? { Self.semantic[name].map { self[keyPath: $0] } }
}
