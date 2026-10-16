import Foundation

public enum JSON {
    public static func encode(_ object: Any) -> Data? {
        guard JSONSerialization.isValidJSONObject([object]) else { return nil }
        return try? JSONSerialization.data(
            withJSONObject: object, options: [.fragmentsAllowed, .withoutEscapingSlashes])
    }

    public static func decode(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    public static func string(_ object: Any) -> String? {
        encode(object).flatMap { String(data: $0, encoding: .utf8) }
    }
}

public let debugEnabled = ProcessInfo.processInfo.environment["CANVAS_DEBUG"] == "1"

public func debugLog(_ message: @autoclosure () -> String) {
    guard debugEnabled else { return }
    FileHandle.standardError.write(Data("canvas: \(message())\n".utf8))
}
