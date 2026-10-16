import Foundation

/// The highlight.js scopes the runtime reduces tokens to (docs/native.md).
public enum HighlightScope: String, CaseIterable {
    case keyword, string, number, comment, title, type, attr, variable, literal
    case builtIn = "built_in"
    case meta, symbol, regexp, addition, deletion, punctuation, property, tag, section
}

/// Token colors from Shiki's `github-dark-default` and `github-light-default`,
/// mapped onto the highlight.js scopes.
public struct HighlightPalette: Equatable {
    /// Plain tokens, the theme's editor foreground.
    public let foreground: RGBA
    let colors: [HighlightScope: RGBA]

    public func color(_ scope: String?) -> RGBA {
        scope.flatMap(HighlightScope.init).flatMap { colors[$0] } ?? foreground
    }

    /// Markdown headings inside code (`section`) are bold in both themes.
    public func isBold(_ scope: String?) -> Bool { scope == HighlightScope.section.rawValue }

    public static let githubDark = palette(
        foreground: "#e6edf3",
        roles: Roles(keyword: "#ff7b72", string: "#a5d6ff", constant: "#79c0ff", comment: "#8b949e",
                     function: "#d2a8ff", entity: "#ffa657", tag: "#7ee787", inserted: "#7ee787", deleted: "#ffa198"))

    public static let githubLight = palette(
        foreground: "#1f2328",
        roles: Roles(keyword: "#cf222e", string: "#0a3069", constant: "#0550ae", comment: "#6e7781",
                     function: "#8250df", entity: "#953800", tag: "#116329", inserted: "#116329", deleted: "#82071e"))

    /// The handful of distinct colors each GitHub theme uses.
    struct Roles {
        let keyword, string, constant, comment, function, entity, tag, inserted, deleted: String
    }

    private static func palette(foreground: String, roles: Roles) -> Self {
        let byScope: [HighlightScope: String] = [
            .keyword: roles.keyword, .string: roles.string, .regexp: roles.string,
            .number: roles.constant, .literal: roles.constant, .attr: roles.constant, .meta: roles.constant,
            .symbol: roles.constant, .property: roles.constant, .section: roles.constant,
            .comment: roles.comment, .title: roles.function,
            .type: roles.entity, .variable: roles.entity, .builtIn: roles.entity,
            .tag: roles.tag, .addition: roles.inserted, .deletion: roles.deleted, .punctuation: foreground
        ]
        let fallback = RGBA(hex: foreground) ?? .black
        return Self(foreground: fallback, colors: byScope.mapValues { RGBA(hex: $0) ?? fallback })
    }
}
