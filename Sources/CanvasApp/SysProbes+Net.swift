import Foundation
import CanvasCore

/// `canvas.sys.net`: receive and send rates summed over the interfaces that
/// are up, leaving out loopback and point-to-point tunnels (whose traffic
/// also crosses a physical interface). Reads the 64-bit counters from
/// `NET_RT_IFLIST2`; `getifaddrs` only has 32-bit ones, which wrap every
/// 4 GB.
final class NetProbe: SysProbe {
    private struct Counters {
        var rx: UInt64
        var tx: UInt64
    }

    private var buffer: [UInt8] = []
    private var previous: [UInt16: Counters] = [:]
    private var current: [UInt16: Counters] = [:]
    private var last: UInt64 = 0

    func sample(now: UInt64) -> Any? {
        guard read() else { return nil }
        defer {
            swap(&previous, &current)
            last = now
        }
        guard last != 0 else { return nil }
        var moved = Counters(rx: 0, tx: 0)
        var totals = Counters(rx: 0, tx: 0)
        for (index, counters) in current {
            totals.rx += counters.rx
            totals.tx += counters.tx
            guard let old = previous[index] else { continue }
            moved.rx += Counter.delta(from: old.rx, to: counters.rx)
            moved.tx += Counter.delta(from: old.tx, to: counters.tx)
        }
        let elapsed = now &- last
        return [
            "rx": Counter.rate(moved.rx, nanoseconds: elapsed).rounded(),
            "tx": Counter.rate(moved.tx, nanoseconds: elapsed).rounded(),
            "rxTotal": totals.rx, "txTotal": totals.tx
        ]
    }

    private func read() -> Bool {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0 else { return false }
        // Room to spare, since interfaces can appear between the two calls.
        if buffer.count < length { buffer = [UInt8](repeating: 0, count: length + length / 4) }
        length = buffer.count
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return false }
        current.removeAll(keepingCapacity: true)
        buffer.withUnsafeBytes { parse(UnsafeRawBufferPointer(rebasing: $0.prefix(length))) }
        return true
    }

    private func parse(_ raw: UnsafeRawBufferPointer) {
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= raw.count {
            let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
            let length = Int(header.ifm_msglen)
            guard length > 0 else { return }
            if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= raw.count {
                record(raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self))
            }
            offset += length
        }
    }

    private func record(_ info: if_msghdr2) {
        let flags = info.ifm_flags
        guard flags & IFF_UP != 0, flags & (IFF_LOOPBACK | IFF_POINTOPOINT) == 0 else { return }
        current[info.ifm_index] = Counters(rx: info.ifm_data.ifi_ibytes, tx: info.ifm_data.ifi_obytes)
    }
}
