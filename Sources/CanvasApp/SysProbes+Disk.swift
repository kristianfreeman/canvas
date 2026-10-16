import Foundation
import IOKit
import CanvasCore

/// `canvas.sys.disk`: read and write rates of the internal drive (all
/// drives when none reports itself internal), and the boot volume's
/// capacity.
final class DiskProbe: SysProbe {
    private struct Bytes {
        var read: UInt64
        var write: UInt64
    }

    private let drivers: [io_registry_entry_t]
    private var previous: Bytes?
    private var last: UInt64 = 0

    init() {
        drivers = Self.drivers()
    }

    deinit {
        drivers.forEach { IOObjectRelease($0) }
    }

    func sample(now: UInt64) -> Any? {
        let bytes = readBytes()
        defer {
            previous = bytes
            last = now
        }
        guard let previous else { return nil }
        let elapsed = now &- last
        let capacity = Self.capacity()
        return [
            "read": Counter.rate(Counter.delta(from: previous.read, to: bytes.read), nanoseconds: elapsed).rounded(),
            "write": Counter.rate(Counter.delta(from: previous.write, to: bytes.write), nanoseconds: elapsed).rounded(),
            "used": capacity.used, "total": capacity.total
        ]
    }

    private func readBytes() -> Bytes {
        var bytes = Bytes(read: 0, write: 0)
        for driver in drivers {
            let property = IORegistryEntryCreateCFProperty(driver, "Statistics" as CFString, kCFAllocatorDefault, 0)
            guard let stats = property?.takeRetainedValue() as? [String: Any] else { continue }
            bytes.read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            bytes.write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return bytes
    }

    private static func capacity() -> (used: UInt64, total: UInt64) {
        var volume = statfs()
        guard statfs("/", &volume) == 0 else { return (0, 0) }
        let blockSize = UInt64(volume.f_bsize)
        let total = volume.f_blocks * blockSize
        return (total - min(volume.f_bavail * blockSize, total), total)
    }

    private static func drivers() -> [io_registry_entry_t] {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var all: [io_registry_entry_t] = []
        while case let service = IOIteratorNext(iterator), service != 0 { all.append(service) }
        let onboard = all.filter(isInternal)
        let kept = onboard.isEmpty ? all : onboard
        for service in all where !kept.contains(service) { IOObjectRelease(service) }
        return kept
    }

    private static func isInternal(_ service: io_registry_entry_t) -> Bool {
        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        let found = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, "Protocol Characteristics" as CFString, kCFAllocatorDefault, options)
        let characteristics = found as? [String: Any]
        return characteristics?["Physical Interconnect Location"] as? String == "Internal"
    }
}
