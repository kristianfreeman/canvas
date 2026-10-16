import Foundation

public enum PanelTheme: String, Sendable {
    case auto, dark, light
}

/// A `show` or `toggle` request as it arrives on the wire.
public struct ShowRequest {
    public var id: String
    public var kind: String
    public var source: String
    public var path: String?
    public var title: String?
    public var data: Any?
    public var buttons: [String]?
    public var wait: Bool
    public var focus: Bool
    public var trace: Bool
    /// Keep reading `{"data":V}` lines from the connection after the answer.
    public var stream: Bool
    /// Any CSS color; nil means the macOS accent color.
    public var accent: String?
    public var theme: PanelTheme?
    public var placement: Placement

    public init(_ json: [String: Any]) throws(RequestError) {
        guard let source = json["source"] as? String else { throw RequestError("missing source") }
        self.source = source
        id = Self.id(in: json)
        kind = (json["kind"] as? String) == "tsx" ? "tsx" : "markdown"
        path = json["path"] as? String
        title = json["title"] as? String
        if let value = json["data"], !(value is NSNull) { data = value }
        buttons = json["buttons"] as? [String]
        wait = json["wait"] as? Bool ?? false
        focus = json["focus"] as? Bool ?? false
        trace = json["trace"] as? Bool ?? false
        stream = json["stream"] as? Bool ?? false
        accent = (json["accent"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        theme = (json["theme"] as? String).flatMap(PanelTheme.init(rawValue:))
        placement = try Placement(json: json)
    }

    /// The panel id a request names, `default` when absent or empty.
    public static func id(in json: [String: Any]) -> String {
        (json["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "default"
    }

    /// The object passed to `window.canvas.render`.
    public var payload: [String: Any] {
        var payload: [String: Any] = ["kind": kind, "source": source, "wait": wait]
        if let title { payload["title"] = title }
        if let data { payload["data"] = data }
        if let buttons { payload["buttons"] = buttons }
        if let theme { payload["theme"] = theme.rawValue }
        if let accent { payload["accent"] = accent }
        return payload
    }
}

public struct RequestError: Error {
    public let message: String
    public init(_ message: String) { self.message = message }
}
