import Foundation
import CanvasCore

/// The process's channels: the store, the panel and CLI subscriptions, and
/// the system sampler they drive. Main thread only.
final class ChannelHub {
    static let shared = ChannelHub()

    enum Subscriber: Hashable {
        case sink(ObjectIdentifier)
        case client(Int)
    }

    let store = ChannelStore()
    private let sampler = SysSampler()
    private var demand = SysDemand<Subscriber>()
    private var sinks: [ObjectIdentifier: PageChannels] = [:]
    private var clients: [Int: [SubscriptionID]] = [:]
    private var nextClient = 0
    /// Where persisted channels are saved; nil keeps them in memory only.
    private var storePath: String?
    private var pendingSave: DispatchWorkItem?

    init() {
        sampler.onSample = { [weak self] samples in self?.publish(samples) }
    }

    func publish(_ message: ChannelMessage) throws(ChannelError) {
        try store.publish(message)
        if message.op == .clear || store.isPersisted(message.channel) { scheduleSave() }
    }

    // MARK: Persistence

    /// Loads the persisted channels saved at `path` and saves them there
    /// from now on.
    func persist(to path: String) {
        storePath = path
        guard let data = FileManager.default.contents(atPath: path) else { return }
        guard let values = JSON.decode(data) as? [String: Any] else {
            debugLog("ignoring \(path): not a JSON object")
            return
        }
        store.restore(values)
    }

    private func scheduleSave() {
        guard storePath != nil, pendingSave == nil else { return }
        let item = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    /// Writes a pending save now, at exit.
    func flush() {
        guard let item = pendingSave else { return }
        item.cancel()
        save()
    }

    private func save() {
        pendingSave = nil
        guard let storePath, let data = JSON.encode(store.persistedValues) else { return }
        do {
            try data.write(to: URL(fileURLWithPath: storePath), options: .atomic)
        } catch {
            debugLog("could not save \(storePath): \(error)")
        }
    }

    private func publish(_ samples: [(SysChannel, Any)]) {
        for (channel, value) in samples where store.subscriberCount(channel.rawValue) > 0 {
            let message = ChannelMessage(channel: channel.rawValue, value: value, keep: SysChannel.historyCapacity)
            _ = try? store.publish(message, from: .server)
        }
    }

    // MARK: CLI subscribers

    /// Subscribes a `sub` connection. `send` gets the replayed history,
    /// then every message. Returns the token for `detach`.
    func attach(_ request: SubRequest, send: @escaping ([String: Any]) -> Void) -> Int {
        nextClient += 1
        let token = nextClient
        request.replay(from: store).forEach(send)
        clients[token] = request.channels.compactMap { channel in
            try? store.subscribe(channel) { update in
                send(["event": "message", "channel": update.channel, "value": update.value])
            }
        }
        request.channels.compactMap(SysChannel.init).forEach { demand.add(.client(token), $0) }
        demandChanged()
        return token
    }

    func detach(_ token: Int) {
        guard let subscriptions = clients.removeValue(forKey: token) else { return }
        subscriptions.forEach(store.unsubscribe)
        demand.removeAll(.client(token))
        demandChanged()
    }

    // MARK: Panels

    /// A panel's hook started listening. The first subscribe for a channel
    /// queues its buffered history; a repeat only changes `every`.
    func subscribe(_ sink: ChannelSink, channel: String, every: Int?) {
        let key = ObjectIdentifier(sink)
        let link = sinks[key] ?? PageChannels(sink: sink)
        sinks[key] = link
        if let sys = SysChannel(rawValue: channel) {
            demand.add(.sink(key), sys, every: every)
            demandChanged()
        }
        guard link.subscriptions[channel] == nil else { return }
        guard let id = try? store.subscribe(channel, { [weak link, store] update in
            link?.queue(update, limit: store.capacity(update.channel) ?? ChannelStore.defaultCapacity)
        }) else { return }
        link.subscriptions[channel] = id
        if let value = store.latest(channel) {
            link.queueFull(channel, value: value, history: store.history(channel))
        }
    }

    func unsubscribe(_ sink: ChannelSink, channel: String) {
        let key = ObjectIdentifier(sink)
        guard let link = sinks[key], let id = link.subscriptions.removeValue(forKey: channel) else { return }
        store.unsubscribe(id)
        link.dropQueued(channel)
        if let sys = SysChannel(rawValue: channel) {
            demand.remove(.sink(key), sys)
            demandChanged()
        }
        if link.subscriptions.isEmpty { sinks[key] = nil }
    }

    /// Drops every subscription of a sink whose panel closed, or whose
    /// content was reset, lost or retired.
    func remove(_ sink: ChannelSink) {
        let key = ObjectIdentifier(sink)
        guard let link = sinks.removeValue(forKey: key) else { return }
        link.subscriptions.values.forEach(store.unsubscribe)
        link.subscriptions.removeAll()
        link.detach()
        demand.removeAll(.sink(key))
        demandChanged()
    }

    /// Whether `sink` holds any subscription, for tests.
    func isSubscribed(_ sink: ChannelSink) -> Bool {
        sinks[ObjectIdentifier(sink)] != nil
    }

    private func demandChanged() {
        sampler.configure(channels: demand.channels, interval: demand.interval)
    }
}
