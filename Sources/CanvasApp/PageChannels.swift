import Foundation
import CanvasCore

/// Where a panel's channel messages go: the page's `canvas.push` or the
/// native context's `canvasNative.push`.
protocol ChannelSink: AnyObject {
    /// False once the sink's panel closed; it only gets a panel back after
    /// a reset, which starts its channels over anyway.
    var receivesPushes: Bool { get }
    func push(_ batch: [[String: Any]], completion: @escaping () -> Void)
}

/// One sink's channel subscriptions and its delivery: at most one push per
/// display frame, and none while the last is still running, so a slow
/// renderer drops intermediate values but never the latest.
final class PageChannels {
    var subscriptions: [String: SubscriptionID] = [:]
    private weak var sink: ChannelSink?
    private var batch = PushBatch()
    private var coalescer = DataCoalescer<Bool>()
    private var inFlight = false

    init(sink: ChannelSink) {
        self.sink = sink
    }

    func queueFull(_ channel: String, value: Any, history: [Any]) {
        batch.replace(channel, value: value, history: history)
        schedule()
    }

    func queue(_ update: ChannelUpdate, limit: Int) {
        batch.add(update, limit: limit)
        schedule()
    }

    func dropQueued(_ channel: String) {
        batch.remove(channel)
    }

    func detach() {
        sink = nil
        _ = batch.take()
    }

    private func schedule() {
        guard !inFlight, let delay = coalescer.offer(true, now: Clock.now()) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(delay))) { [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        guard coalescer.flush(now: Clock.now()) != nil, !batch.isEmpty, let sink else { return }
        guard sink.receivesPushes else {
            ChannelHub.shared.remove(sink)
            return
        }
        inFlight = true
        sink.push(batch.take()) { [weak self] in self?.delivered() }
    }

    private func delivered() {
        inFlight = false
        if !batch.isEmpty { schedule() }
    }
}
