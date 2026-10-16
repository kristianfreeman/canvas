import Foundation

/// A distance in points or a percentage of the visible width or height. The
/// sign is kept apart from the magnitude so `-0%` still means "from the far
/// edge".
public struct Length: Equatable, Sendable, CustomStringConvertible {
    public enum Unit: Sendable {
        case points, percent
    }

    public var magnitude: CGFloat
    public var unit: Unit
    public var isNegative: Bool

    public init(_ value: CGFloat, _ unit: Unit = .points) {
        self.init(magnitude: abs(value), unit: unit, negative: value.sign == .minus)
    }

    public init(magnitude: CGFloat, unit: Unit, negative: Bool) {
        self.magnitude = magnitude
        self.unit = unit
        isNegative = negative
    }

    public static func points(_ value: CGFloat) -> Self { Self(value) }
    public static func percent(_ value: CGFloat) -> Self { Self(value, .percent) }

    /// The magnitude in points; percentages are of `extent`, rounded down.
    public func resolved(in extent: CGFloat) -> CGFloat {
        unit == .points ? magnitude : (extent * magnitude / 100).rounded(.down)
    }

    public var description: String {
        let sign = isNegative ? "-" : ""
        return unit == .points ? "\(sign)\(magnitude)" : "\(sign)\(magnitude)%"
    }

    /// A JSON number, `"N%"`, or a numeric string such as `"-0"`.
    public init?(wire value: Any) {
        if let number = Wire.number(value) {
            self.init(number)
            return
        }
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces) else { return nil }
        let percent = text.hasSuffix("%")
        let digits = percent ? String(text.dropLast()) : text
        guard let number = Double(digits), number.isFinite else { return nil }
        self.init(magnitude: CGFloat(abs(number)), unit: percent ? .percent : .points, negative: digits.hasPrefix("-"))
    }
}

/// `--at X,Y`: offsets from the visible frame's top-left corner, y down.
/// A negative X measures the right edge from the right, a negative Y the
/// bottom edge from the bottom.
public struct AtPoint: Equatable, Sendable {
    public var x: Length
    public var y: Length

    public init(x: Length, y: Length) {
        self.x = x
        self.y = y
    }
}

public enum ScreenSelector: Equatable, Sendable {
    case mouse, main, focused
    /// 1-based, matching `ScreenInfo.index`.
    case index(Int)
    /// A case-insensitive substring of the display name.
    case name(String)

    public init?(wire value: Any) {
        if let number = Wire.number(value) {
            guard number >= 1, number == number.rounded() else { return nil }
            self = .index(Int(number))
            return
        }
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        self.init(text: text)
    }

    private init?(text: String) {
        switch text.lowercased() {
        case "mouse": self = .mouse
        case "main": self = .main
        case "focused": self = .focused
        default:
            guard text.allSatisfy(\.isASCIIDigit) else {
                self = .name(text)
                return
            }
            guard let index = Int(text), index >= 1 else { return nil }
            self = .index(index)
        }
    }
}

extension Placement {
    public enum Position: String, CaseIterable, Sendable {
        case center, top, bottom, left, right
        case topLeft = "top-left", topRight = "top-right"
        case bottomLeft = "bottom-left", bottomRight = "bottom-right"
        case mouse

        /// The anchor of a preset, which is also its alignment on screen.
        /// `mouse` has none until it is placed.
        public var anchor: Anchor? { Self.anchors[self] }

        private static let anchors: [Self: Anchor] = [
            .center: Anchor(.center, .center),
            .top: Anchor(.top, .center),
            .bottom: Anchor(.bottom, .center),
            .left: Anchor(.center, .left),
            .right: Anchor(.center, .right),
            .topLeft: Anchor(.top, .left),
            .topRight: Anchor(.top, .right),
            .bottomLeft: Anchor(.bottom, .left),
            .bottomRight: Anchor(.bottom, .right)
        ]
    }

    public enum Level: String, CaseIterable, Sendable {
        case normal, floating, top
    }

    public enum Spaces: String, CaseIterable, Sendable {
        case all, current
    }
}

/// Typed reads of JSON values: booleans and numbers kept apart, since both
/// arrive as `NSNumber`.
enum Wire {
    static func isBool(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    static func number(_ value: Any) -> CGFloat? {
        guard !isBool(value), let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        return double.isFinite ? CGFloat(double) : nil
    }

    static func choice<T: RawRepresentable & CaseIterable>(_ value: Any, _ field: Placement.Field) throws(RequestError)
        -> T where T.RawValue == String {
        if let raw = value as? String, let choice = T(rawValue: raw) { return choice }
        let choices = T.allCases.map(\.rawValue).joined(separator: ", ")
        throw RequestError("invalid \(field.rawValue) \(describe(value)): expected one of \(choices)")
    }

    static func describe(_ value: Any) -> String {
        JSON.string(value) ?? "\(value)"
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
