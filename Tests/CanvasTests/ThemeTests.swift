import CanvasCore
import Foundation
import Testing

@Suite struct ThemeTests {
    /// `--name: value` pairs from the `[data-theme='mode']` block of styles.css.
    static func cssTokens(_ mode: ThemeMode) throws -> [String: String] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../web/src/styles.css")
        let css = try String(contentsOf: url, encoding: .utf8)
        let marker = "[data-theme='\(mode.rawValue)'] {"
        let start = try #require(css.range(of: marker)).upperBound
        let block = css[start...].prefix { $0 != "}" }
        var tokens: [String: String] = [:]
        for line in block.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).dropLast().split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].hasPrefix("--") else { continue }
            tokens[String(parts[0].dropFirst(2))] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return tokens
    }

    static func tokenTable(_ tokens: ThemeTokens) -> [String: RGBA] {
        [
            "bg": tokens.bg, "fg": tokens.fg, "fg-soft": tokens.fgSoft, "fg-muted": tokens.fgMuted,
            "fg-subtle": tokens.fgSubtle, "surface": tokens.surface, "surface-raised": tokens.surfaceRaised,
            "border": tokens.border, "border-strong": tokens.borderStrong, "border-hover": tokens.borderHover,
            "card": tokens.card, "card-hover": tokens.cardHover, "field": tokens.field, "code-bg": tokens.codeBg,
            "inline-code-bg": tokens.inlineCodeBg, "kbd-bg": tokens.kbdBg, "kbd-border": tokens.kbdBorder,
            "kbd-edge": tokens.kbdEdge, "track": tokens.track
        ]
    }

    @Test(arguments: ThemeMode.allCases)
    func tokensMatchStylesCSS(mode: ThemeMode) throws {
        let css = try Self.cssTokens(mode)
        let tokens = ThemeTokens.of(mode)
        for (name, color) in Self.tokenTable(tokens) {
            let value = try #require(css[name], "styles.css has no --\(name) for \(mode)")
            #expect(CSSColor.parse(value) == color, "--\(name): css \(value), swift \(color)")
        }
        for hue in Hue.allCases {
            #expect(CSSColor.parse(css[hue.rawValue] ?? "") == tokens.hue(hue), "--\(hue.rawValue) in \(mode)")
        }
        #expect(css["warning"] == "var(--\(tokens.warningHue.rawValue))")
        #expect(css["ink"] == "\(Int(tokens.ink * 100))%")
    }

    @Test func semanticNamesFollowTheMode() {
        let dark = Theme(mode: .dark)
        let light = Theme(mode: .light)
        #expect(dark.resolve("warning") == RGBA(hex: "#ffd60a"))
        #expect(light.resolve("warning") == RGBA(hex: "#ff9500"))
        #expect(dark.resolve("success") == RGBA(hex: "#30d158"))
        #expect(light.resolve("danger") == RGBA(hex: "#ff3b30"))
        #expect(dark.resolve("info") == RGBA(hex: "#0a84ff"))
        #expect(light.resolve("muted") == RGBA(hex: "#6b6b6b"))
        #expect(dark.resolve("teal") == RGBA(hex: "#40c8e0"))
        #expect(light.resolve("teal") == RGBA(hex: "#30b0c7"))
        #expect(Theme(mode: .dark, accent: "#bf5af2").resolve("accent") == RGBA(hex: "#bf5af2"))
    }

    @Test func cssStringsResolve() {
        let theme = Theme(mode: .dark)
        #expect(theme.resolve("#abc") == RGBA(hex: "#aabbcc"))
        #expect(theme.resolve("#11223380") == RGBA(red: 17 / 255, green: 34 / 255, blue: 51 / 255, alpha: 128 / 255))
        #expect(theme.resolve("rgb(255, 0, 0)") == RGBA(red: 1, green: 0, blue: 0))
        #expect(theme.resolve("rgba(0, 0, 255, 0.5)") == RGBA(red: 0, green: 0, blue: 1, alpha: 0.5))
        #expect(theme.resolve("rgb(0 128 0 / 25%)") == RGBA(red: 0, green: 128 / 255, blue: 0, alpha: 0.25))
        #expect(theme.resolve("rgb(100%, 0%, 50%)") == RGBA(red: 1, green: 0, blue: 0.5))
        #expect(theme.resolve("  WHITE ") == .white)
        #expect(theme.resolve("transparent") == .clear)
        #expect(theme.resolve("hsl(0, 100%, 50%)") == RGBA(red: 1, green: 0, blue: 0))
        #expect(theme.resolve("hsl(240deg 100% 50%)") == RGBA(red: 0, green: 0, blue: 1))
        #expect(theme.resolve("hsl(120, 100%, 25%)").hex == "#008000")
    }

    @Test(arguments: [
        "", "   ", "accentish", "#12", "#12345", "#gggggg", "rgb(1, 2)", "rgb(1, 2, 3, 4, 5)", "rgb(a, b, c)",
        "rgb(1, 2, 3", "rgb(1,, 3)", "rgb(inf, 0, 0)", "rgb(nan, 0, 0)", "hsl(0, 100, 50)", "var(--red)",
        "url(x)", "rgb(1 2 3 / 4 / 5)"
    ])
    func invalidColorsFallBack(text: String) {
        let fallback = RGBA(hex: "#123456") ?? .black
        #expect(Theme(mode: .light).resolve(text, fallback: fallback) == fallback, "\(text)")
        #expect(Theme(mode: .dark).resolve(nil) == Theme(mode: .dark).accent)
    }

    @Test func accentDefaultsAndForeground() {
        let plain = Theme(mode: .dark)
        #expect(plain.accent == RGBA(hex: "#0a84ff"))
        #expect(plain.accentForeground == .white)
        #expect(Theme(mode: .light, accent: "#ffcc00").accentForeground == .black)
        #expect(Theme(mode: .light, accent: "#007aff").accentForeground == .white)
        #expect(Theme(mode: .light, accent: "not a color").accent == RGBA(hex: "#007aff"))
    }

    /// The 3:1 bar sits between these two grays: #949494 has luminance just
    /// under 0.3 (contrast with white above 3), #959595 just over.
    @Test func contrastRuleMatchesColorsTS() {
        #expect(RGBA(hex: "#949494")?.contrastForeground == .white)
        #expect(RGBA(hex: "#959595")?.contrastForeground == .black)
        #expect(RGBA(hex: "#ffd60a")?.contrastForeground == .black)
        #expect(RGBA(hex: "#30d158")?.contrastForeground == .black)
        #expect(RGBA(hex: "#bf5af2")?.contrastForeground == .white)
        #expect(abs((RGBA(hex: "#ffffff")?.luminance ?? 0) - 1) < 1e-9)
    }

    @Test func mixingMatchesCSSColorMix() throws {
        let red = try #require(RGBA(hex: "#ff0000"))
        #expect(red.mixed(0.12, with: .clear) == red.opacity(0.12))
        #expect(red.mixed(0.5, with: .white).hex == "#ff8080")
        let light = Theme(mode: .light)
        #expect(light.ink(red) == red.mixed(0.72, with: light.tokens.fg))
        #expect(Theme(mode: .dark).ink(red) == red)
    }

    @Test func highlightPalettes() {
        let dark = HighlightPalette.githubDark
        let light = HighlightPalette.githubLight
        #expect(dark.color("keyword") == RGBA(hex: "#ff7b72"))
        #expect(light.color("keyword") == RGBA(hex: "#cf222e"))
        #expect(dark.color(nil) == RGBA(hex: "#e6edf3"))
        #expect(light.color("no-such-scope") == light.foreground)
        for scope in HighlightScope.allCases where scope != .punctuation {
            #expect(dark.color(scope.rawValue) != dark.foreground, "\(scope) dark")
            #expect(light.color(scope.rawValue) != light.foreground, "\(scope) light")
        }
        #expect(dark.isBold("section") && !dark.isBold("keyword"))
        #expect(Theme(mode: .light).highlight == light)
    }
}
