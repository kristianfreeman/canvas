/// One core's cumulative tick counters, as `host_processor_info` reports
/// them. They are 32-bit and wrap.
public struct CPUTicks: Equatable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// Busy fractions, each 0...1.
public struct CPUUsage: Equatable {
    public var total: Double
    public var cores: [Double]

    public init(total: Double, cores: [Double]) {
        self.total = total
        self.cores = cores
    }
}

public enum CPULoad {
    /// Usage between two readings of every core. Nil when the core count
    /// changed, so the caller starts over from `current`.
    public static func usage(from previous: [CPUTicks], to current: [CPUTicks]) -> CPUUsage? {
        guard previous.count == current.count, !current.isEmpty else { return nil }
        var busyTotal: UInt64 = 0
        var allTotal: UInt64 = 0
        var cores: [Double] = []
        cores.reserveCapacity(current.count)
        for (old, new) in zip(previous, current) {
            let (busy, all) = delta(from: old, to: new)
            busyTotal += busy
            allTotal += all
            cores.append(fraction(busy, of: all))
        }
        return CPUUsage(total: fraction(busyTotal, of: allTotal), cores: cores)
    }

    private static func delta(from old: CPUTicks, to new: CPUTicks) -> (busy: UInt64, all: UInt64) {
        let busy = UInt64(new.user &- old.user) + UInt64(new.system &- old.system) + UInt64(new.nice &- old.nice)
        return (busy, busy + UInt64(new.idle &- old.idle))
    }

    private static func fraction(_ part: UInt64, of whole: UInt64) -> Double {
        whole == 0 ? 0 : min(1, Double(part) / Double(whole))
    }
}

/// Monotonic byte counters (network, disk) turned into rates.
public enum Counter {
    /// How far a counter of `width` bits moved. A drop near the top of the
    /// range is a wrap; any other drop is a reset (the interface or driver
    /// went away and came back), which counts as no movement.
    public static func delta(from previous: UInt64, to current: UInt64, width: Int = 64) -> UInt64 {
        if current >= previous { return current - previous }
        guard width < 64 else { return 0 }
        let range = UInt64(1) << UInt64(width)
        guard previous >= range / 2, previous < range else { return 0 }
        return range - previous + current
    }

    /// Units per second for `delta` over `nanoseconds`.
    public static func rate(_ delta: UInt64, nanoseconds: UInt64) -> Double {
        nanoseconds == 0 ? 0 : Double(delta) * 1_000_000_000 / Double(nanoseconds)
    }
}

public enum TopN {
    /// The `count` highest elements, highest first. Ties keep their input
    /// order. Runs in one pass without sorting everything.
    public static func select<Element>(
        _ elements: [Element], count: Int, isHigher: (Element, Element) -> Bool
    ) -> [Element] {
        guard count > 0 else { return [] }
        var top: [Element] = []
        top.reserveCapacity(min(count, elements.count) + 1)
        for element in elements {
            if top.count == count, let last = top.last, !isHigher(element, last) { continue }
            let index = top.firstIndex { isHigher(element, $0) } ?? top.count
            top.insert(element, at: index)
            if top.count > count { top.removeLast() }
        }
        return top
    }
}
