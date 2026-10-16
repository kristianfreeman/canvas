import Foundation

extension Placement {
    typealias Parser = (inout Placement, Any) throws -> Void

    static func parse(_ field: Field, _ value: Any, into placement: inout Placement) throws(RequestError) {
        do {
            try parsers[field]?(&placement, value)
        } catch let error as RequestError {
            throw error
        } catch {
            throw RequestError("invalid \(field.rawValue): \(error)")
        }
    }

    private static let parsers: [Field: Parser] = [
        .position: { $0.position = try Wire.choice($1, .position) },
        .at: { $0.at = try atPoint($1) },
        .screen: { $0.screen = try screenSelector($1) },
        .margin: { $0.margin = try margin($1) },
        .width: { $0.width = try size($1, .width) },
        .height: { $0.height = try size($1, .height) },
        .minHeight: { $0.minHeight = try size($1, .minHeight) },
        .maxHeight: { $0.maxHeight = try size($1, .maxHeight) },
        .resizable: { $0.resizable = try flag($1, .resizable) },
        .level: { $0.level = try Wire.choice($1, .level) },
        .spaces: { $0.spaces = try Wire.choice($1, .spaces) },
        .pin: { $0.pin = try flag($1, .pin) },
        .clickThrough: { $0.clickThrough = try flag($1, .clickThrough) },
        .opacity: { $0.opacity = try opacity($1) },
        .stack: { $0.stack = try groupName($1) },
        .forget: { $0.forget = try flag($1, .forget) }
    ]

    private static func invalid(_ field: Field, _ value: Any, _ expected: String) -> RequestError {
        RequestError("invalid \(field.rawValue) \(Wire.describe(value)): expected \(expected)")
    }

    private static func flag(_ value: Any, _ field: Field) throws(RequestError) -> Bool {
        guard Wire.isBool(value), let flag = value as? Bool else { throw invalid(field, value, "true or false") }
        return flag
    }

    private static func margin(_ value: Any) throws(RequestError) -> CGFloat {
        guard let number = Wire.number(value), number >= 0 else { throw invalid(.margin, value, "a number >= 0") }
        return number
    }

    private static func opacity(_ value: Any) throws(RequestError) -> CGFloat {
        guard let number = Wire.number(value), (0...1).contains(number) else {
            throw invalid(.opacity, value, "a number from 0 to 1")
        }
        return number
    }

    /// A positive number of points or a positive percentage.
    private static func size(_ value: Any, _ field: Field) throws(RequestError) -> Length {
        guard let length = Length(wire: value), !length.isNegative, length.magnitude > 0 else {
            throw invalid(field, value, "a positive number or \"N%\"")
        }
        return length
    }

    private static func atPoint(_ value: Any) throws(RequestError) -> AtPoint {
        guard let object = value as? [String: Any], let x = object["x"].flatMap(Length.init(wire:)),
              let y = object["y"].flatMap(Length.init(wire:)) else {
            throw invalid(.at, value, #"{"x": number | "N%", "y": number | "N%"}"#)
        }
        return AtPoint(x: x, y: y)
    }

    private static func screenSelector(_ value: Any) throws(RequestError) -> ScreenSelector {
        guard let selector = ScreenSelector(wire: value) else {
            throw invalid(.screen, value, "mouse, main, focused, a display number from 1, or part of a display name")
        }
        return selector
    }

    private static func groupName(_ value: Any) throws(RequestError) -> String {
        guard let name = (value as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
            throw invalid(.stack, value, "a group name")
        }
        return name
    }
}
