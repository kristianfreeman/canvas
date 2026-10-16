import Foundation

/// Where a native panel's events go: function props back into its JS
/// context, results and closing to its caller.
protocol NativeEvents: AnyObject {
    /// Calls the function prop `{"$fn": fn}` with JSON-able `args`.
    func invoke(_ fn: Int, _ args: [Any])
    /// Posts `result` with `value`.
    func submit(_ value: Any)
    func close()
    /// A link was clicked. Only http, https and mailto URLs get here.
    func open(_ url: URL)
}

enum LinkPolicy {
    static let schemes: Set<String> = ["http", "https", "mailto"]

    static func allows(_ url: URL) -> Bool {
        url.scheme.map { schemes.contains($0.lowercased()) } ?? false
    }

    /// Opens `url` through `events` when it's allowed; anything else is dropped.
    static func open(_ url: URL, with events: NativeEvents?) {
        if allows(url) { events?.open(url) }
    }
}

/// Holds the events target weakly, so the view tree never keeps a panel alive.
struct EventsRef {
    weak var target: NativeEvents?
}
