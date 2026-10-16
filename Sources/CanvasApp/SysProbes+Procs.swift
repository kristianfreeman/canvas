import Foundation
import CanvasCore

/// `canvas.sys.procs`: the busiest processes, from CPU time deltas.
/// Processes the user may not inspect are left out.
final class ProcsProbe: SysProbe {
    private struct Usage {
        let pid: Int32
        let cpu: Double
        let mem: UInt64
    }

    private var pids = [Int32](repeating: 0, count: 2048)
    private var previous: [Int32: UInt64] = [:]
    private var current: [Int32: UInt64] = [:]
    private var usages: [Usage] = []
    private var names: [Int32: String] = [:]
    private var nameBuffer = [UInt8](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
    private var last: UInt64 = 0

    func sample(now: UInt64) -> Any? {
        let count = listPids()
        let elapsed = now &- last
        current.removeAll(keepingCapacity: true)
        usages.removeAll(keepingCapacity: true)
        for pid in pids.prefix(count) where pid > 0 { measure(pid, elapsed: elapsed) }
        defer {
            swap(&previous, &current)
            last = now
        }
        guard last != 0 else { return nil }
        for pid in names.keys where current[pid] == nil { names[pid] = nil }
        let top = TopN.select(usages, count: SysChannel.processCount) { lhs, rhs in
            lhs.cpu > rhs.cpu || (lhs.cpu == rhs.cpu && lhs.mem > rhs.mem)
        }
        return top.map { ["pid": Int($0.pid), "name": name($0.pid), "cpu": trimmed($0.cpu), "mem": $0.mem] }
    }

    private func listPids() -> Int {
        while true {
            let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.stride)))
            guard count >= pids.count else { return max(count, 0) }
            pids = [Int32](repeating: 0, count: pids.count * 2)
        }
    }

    private func measure(_ pid: Int32, elapsed: UInt64) {
        var info = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        guard status == 0 else { return }
        // The times are in Mach ticks, not nanoseconds, on Apple silicon.
        let time = Clock.nanoseconds(ticks: info.ri_user_time &+ info.ri_system_time)
        current[pid] = time
        guard let old = previous[pid], time >= old, elapsed > 0 else { return }
        usages.append(Usage(pid: pid, cpu: Double(time - old) / Double(elapsed), mem: info.ri_resident_size))
    }

    private func name(_ pid: Int32) -> String {
        if let cached = names[pid] { return cached }
        let length = Int(proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)))
        let decoded = length > 0 ? String(bytes: nameBuffer[0..<length], encoding: .utf8) : nil
        let name = decoded ?? String(pid)
        names[pid] = name
        return name
    }
}
