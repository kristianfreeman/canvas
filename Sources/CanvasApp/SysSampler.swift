import Foundation
import CanvasCore

/// One system channel's reader. Probes run on the sampler's queue.
protocol SysProbe: AnyObject {
    /// The channel's value now, or nil while a rate probe has only its
    /// first reading.
    func sample(now: UInt64) -> Any?
}

/// Reads the demanded `canvas.sys.*` channels on a background queue, at
/// the hub's interval, and hands each round to `onSample` on the main
/// thread. It holds no timer and no probes while nothing subscribes.
final class SysSampler {
    /// Main thread.
    var onSample: (([(SysChannel, Any)]) -> Void)?

    private let queue = DispatchQueue(label: "canvas.sys-sampler", qos: .utility)
    // Everything below belongs to `queue`.
    private var timer: DispatchSourceTimer?
    private var interval = 0
    private var probes: [SysChannel: SysProbe] = [:]

    /// From the main thread, whenever the demand changes. A nil interval
    /// stops the sampler.
    func configure(channels: Set<SysChannel>, interval: Int?) {
        queue.async { [self] in apply(channels: interval == nil ? [] : channels, interval: interval ?? 0) }
    }

    private func apply(channels: Set<SysChannel>, interval: Int) {
        let added = updateProbes(channels)
        guard !channels.isEmpty else {
            stopTimer()
            return
        }
        if timer == nil || interval != self.interval { startTimer(interval) }
        if !added.isEmpty { tick(added) }
    }

    /// Drops the probes nobody wants, so a later subscriber starts from a
    /// fresh baseline, and creates the new ones. Returns the new channels.
    private func updateProbes(_ channels: Set<SysChannel>) -> Set<SysChannel> {
        for channel in probes.keys where !channels.contains(channel) { probes[channel] = nil }
        let added = channels.filter { probes[$0] == nil }
        for channel in added { probes[channel] = Self.factories[channel]?() }
        return added
    }

    private func startTimer(_ interval: Int) {
        stopTimer()
        self.interval = interval
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let period = DispatchTimeInterval.milliseconds(interval)
        timer.schedule(deadline: .now() + period, repeating: period, leeway: .milliseconds(max(interval / 10, 5)))
        timer.setEventHandler { [weak self] in self?.tick(nil) }
        self.timer = timer
        timer.resume()
        debugLog("sampler every \(interval) ms")
    }

    private func stopTimer() {
        guard let timer else { return }
        timer.cancel()
        self.timer = nil
        debugLog("sampler stopped")
    }

    /// Samples `only` those channels, or all of them.
    private func tick(_ only: Set<SysChannel>?) {
        let now = Clock.now()
        var samples: [(SysChannel, Any)] = []
        samples.reserveCapacity(probes.count)
        for (channel, probe) in probes where only?.contains(channel) ?? true {
            if let value = probe.sample(now: now) { samples.append((channel, value)) }
        }
        guard !samples.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in self?.onSample?(samples) }
    }

    private static let factories: [SysChannel: () -> SysProbe] = [
        .cpu: { CPUProbe() },
        .memory: { MemoryProbe() },
        .net: { NetProbe() },
        .disk: { DiskProbe() },
        .procs: { ProcsProbe() },
        .battery: { BatteryProbe() },
        .thermal: { ThermalProbe() }
    ]
}
