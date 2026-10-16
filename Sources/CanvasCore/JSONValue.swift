import Foundation

/// A JSON value as the native runtime sends it. A function prop arrives as
/// `{"$fn": N}` and decodes to `.function(N)`.
public enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([Self])
    case object([String: Self])
    case function(Int)

    public init(_ any: Any?) {
        switch any {
        case nil, is NSNull: self = .null
        case let number as NSNumber: self = Self.number(number)
        case let string as String: self = .string(string)
        case let array as [Any]: self = .array(array.map(Self.init))
        case let object as [String: Any]: self = Self.object(object)
        default: self = .null
        }
    }

    private static func number(_ number: NSNumber) -> Self {
        CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
    }

    private static func object(_ object: [String: Any]) -> Self {
        if object.count == 1, let id = object["$fn"] as? NSNumber { return .function(id.intValue) }
        return .object(object.mapValues(Self.init))
    }

    /// Back to Foundation objects, for passing to JavaScript or JSONSerialization.
    public var any: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): value
        case .number(let value): value
        case .string(let value): value
        case .array(let values): values.map(\.any)
        case .object(let values): values.mapValues(\.any)
        case .function(let id): ["$fn": id]
        }
    }

    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public var number: Double? { if case .number(let value) = self { value } else { nil } }
    /// True only for `true`; anything else, including a missing value, is false.
    public var isTrue: Bool { self == .bool(true) }
    public var array: [Self]? { if case .array(let value) = self { value } else { nil } }
    public var object: [String: Self]? { if case .object(let value) = self { value } else { nil } }
    public var function: Int? { if case .function(let value) = self { value } else { nil } }

    public subscript(key: String) -> Self? { object?[key] }
}
