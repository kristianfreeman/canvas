/// When the server keeps a WebKit page for the fallback renderer, from
/// `warm`, `idle_minutes` and `linger_seconds` in the config.
public struct WarmPolicy: Equatable {
    public let mode: Config.Warm
    public let idleSeconds: Double
    public let lingerSeconds: Double

    public init(_ config: Config) {
        mode = config.warm
        idleSeconds = Double(config.idleMinutes) * 60
        lingerSeconds = Double(config.lingerSeconds)
    }

    /// Whether to load a page before anyone needs one: at launch and after a
    /// show takes the parked page.
    public var prefills: Bool { mode == .always || mode == .idle }

    /// Whether a closed panel's page can go back to the pool.
    public var keepsPage: Bool { mode != .never }

    /// Seconds after the last web panel closes before the parked page is
    /// dropped, or nil to keep it.
    public func trimDelay(visiblePanels: Int) -> Double? {
        guard visiblePanels == 0 else { return nil }
        switch mode {
        case .idle: return idleSeconds
        case .linger: return lingerSeconds
        case .always, .never: return nil
        }
    }
}
