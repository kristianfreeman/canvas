import AppKit
import CanvasCore

/// Keeps one parked host of one renderer ready, so a new panel only has to
/// render. Its rules decide whether it fills up front and how long a
/// parked host stays.
final class WarmPool {
    let renderer: Renderer
    private let rules: PoolRules
    private let make: () -> PanelHost
    private var parked: PanelHost?
    private var refillPending = false
    private var trimItem: DispatchWorkItem?
    /// How many open panels use this pool's renderer, for the trim timer.
    var openPanels: () -> Int = { 0 }

    init(renderer: Renderer, rules: PoolRules, make: @escaping () -> PanelHost) {
        self.renderer = renderer
        self.rules = rules
        self.make = make
    }

    var hasParkedHost: Bool { parked != nil }

    /// The parked host, or a new one (a new page loads while the caller
    /// renders into it).
    func take() -> (host: PanelHost, pooled: Bool) {
        cancelTrim()
        if let host = parked {
            parked = nil
            return (host, true)
        }
        return (make(), false)
    }

    func fill() {
        guard rules.prefills, parked == nil else { return }
        let host = make()
        host.park(at: PanelHost.parkingFrame)
        parked = host
        debugLog("\(renderer.rawValue) pool filled")
        panelsChanged()
    }

    /// After a panel appears: refill once the main loop is idle, off the
    /// critical path of the show that emptied the pool.
    func refillWhenIdle() {
        guard rules.prefills, parked == nil, !refillPending else { return }
        refillPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            MainIdle.once { [weak self] in
                self?.refillPending = false
                self?.fill()
            }
        }
    }

    /// A host this pool's renderer no longer shows: reset and parked if the
    /// pool is empty, otherwise torn down.
    func recycle(_ host: PanelHost) {
        host.settle()
        guard rules.keepsHost, parked == nil, host.renderer == renderer else {
            host.tearDown()
            return
        }
        host.content.reset()
        host.park(at: PanelHost.parkingFrame)
        parked = host
        panelsChanged()
    }

    /// Drops the parked host (for WebKit, so its content process can exit).
    func trim() {
        cancelTrim()
        guard let host = parked else { return }
        parked = nil
        host.tearDown()
        debugLog("\(renderer.rawValue) pool trimmed")
    }

    /// Starts or cancels the trim timer when panels open, close or change
    /// renderer.
    func panelsChanged() {
        cancelTrim()
        guard parked != nil, let delay = rules.trimDelay(openPanels: openPanels()) else { return }
        let item = DispatchWorkItem { [weak self] in self?.trim() }
        trimItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelTrim() {
        trimItem?.cancel()
        trimItem = nil
    }
}

/// Work for when the main run loop is about to sleep.
enum MainIdle {
    static func once(_ work: @escaping () -> Void) {
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, false, 0) { _, _ in work() }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}
