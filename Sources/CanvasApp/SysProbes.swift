import Foundation
import CanvasCore

/// The host port, fetched once: every `mach_host_self` call adds a send
/// right.
let machHost = mach_host_self()

/// Fractions trimmed to three decimals, which is all a chart can show.
func trimmed(_ value: Double) -> Double {
    (value * 1000).rounded() / 1000
}

/// `canvas.sys.cpu`: per-core busy fractions from tick deltas.
final class CPUProbe: SysProbe {
    private var previous: [CPUTicks] = []
    private var current: [CPUTicks] = []

    func sample(now _: UInt64) -> Any? {
        guard Self.read(into: &current) else { return nil }
        defer { swap(&previous, &current) }
        guard let usage = CPULoad.usage(from: previous, to: current) else { return nil }
        return ["total": trimmed(usage.total), "cores": usage.cores.map(trimmed)]
    }

    private static func read(into ticks: inout [CPUTicks]) -> Bool {
        var cpus: natural_t = 0
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        guard host_processor_info(machHost, PROCESSOR_CPU_LOAD_INFO, &cpus, &info, &count) == KERN_SUCCESS,
              let info else { return false }
        defer {
            let size = vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }
        ticks.removeAll(keepingCapacity: true)
        for cpu in 0..<Int(cpus) {
            let state = info + cpu * Int(CPU_STATE_MAX)
            ticks.append(CPUTicks(
                user: UInt32(bitPattern: state[Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: state[Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: state[Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: state[Int(CPU_STATE_NICE)])))
        }
        return true
    }
}

/// `canvas.sys.memory`, counted the way Activity Monitor does: used is app
/// memory plus wired plus compressed.
final class MemoryProbe: SysProbe {
    private let total = ProcessInfo.processInfo.physicalMemory
    private let pageSize = UInt64(vm_kernel_page_size)

    func sample(now _: UInt64) -> Any? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(machHost, HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        let app = UInt64(stats.internal_page_count &- min(stats.purgeable_count, stats.internal_page_count)) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        return [
            "total": total, "used": app + wired + compressed, "app": app,
            "wired": wired, "compressed": compressed, "swapUsed": Self.swapUsed()
        ]
    }

    private static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }
}

/// `canvas.sys.thermal`.
final class ThermalProbe: SysProbe {
    func sample(now _: UInt64) -> Any? {
        ["state": Self.name(ProcessInfo.processInfo.thermalState)]
    }

    private static func name(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        default: return "nominal"
        }
    }
}
