import Foundation

/// An sRGB color with straight alpha. Components are 0...1.
public struct RGBA: Equatable, Hashable, CustomStringConvertible {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.unit(red)
        self.green = Self.unit(green)
        self.blue = Self.unit(blue)
        self.alpha = Self.unit(alpha)
    }

    /// `#rgb`, `#rgba`, `#rrggbb` or `#rrggbbaa`.
    public init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        var digits = String(hex.dropFirst())
        if digits.count == 3 || digits.count == 4 { digits = String(digits.flatMap { [$0, $0] }) }
        guard digits.count == 6 || digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
        let full = digits.count == 6 ? value << 8 | 0xFF : value
        self.init(red: Double(full >> 24 & 0xFF) / 255, green: Double(full >> 16 & 0xFF) / 255,
                  blue: Double(full >> 8 & 0xFF) / 255, alpha: Double(full & 0xFF) / 255)
    }

    public static let white = Self(red: 1, green: 1, blue: 1)
    public static let black = Self(red: 0, green: 0, blue: 0)
    public static let clear = Self(red: 0, green: 0, blue: 0, alpha: 0)

    /// `#rrggbb`, or `#rrggbbaa` when not opaque.
    public var hex: String {
        let parts = alpha < 1 ? [red, green, blue, alpha] : [red, green, blue]
        return "#" + parts.map { String(format: "%02x", Self.byte($0)) }.joined()
    }

    public var description: String { hex }

    /// The same color with its alpha multiplied by `factor`.
    public func opacity(_ factor: Double) -> Self {
        Self(red: red, green: green, blue: blue, alpha: alpha * factor)
    }

    /// CSS `color-mix(in srgb, self fraction, other)`, premultiplied as CSS mixes.
    public func mixed(_ fraction: Double, with other: Self) -> Self {
        let share = Self.unit(fraction)
        let alpha = alpha * share + other.alpha * (1 - share)
        guard alpha > 0 else { return .clear }
        func channel(_ mine: Double, _ theirs: Double) -> Double {
            (mine * self.alpha * share + theirs * other.alpha * (1 - share)) / alpha
        }
        return Self(red: channel(red, other.red), green: channel(green, other.green),
                    blue: channel(blue, other.blue), alpha: alpha)
    }

    /// WCAG relative luminance, ignoring alpha.
    public var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// White when it reaches 3:1 against this color (WCAG for UI and bold text), else black.
    public var contrastForeground: Self {
        1.05 / (luminance + 0.05) >= 3 ? .white : .black
    }

    static func byte(_ value: Double) -> Int { Int((unit(value) * 255).rounded()) }

    static func unit(_ value: Double) -> Double { value.isNaN ? 0 : min(max(value, 0), 1) }
}
