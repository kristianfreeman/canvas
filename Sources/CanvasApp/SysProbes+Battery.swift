import Foundation
import IOKit.ps
import CanvasCore

/// `canvas.sys.battery`: the internal battery, or null on a Mac without
/// one. `source` is `"ac"` or `"battery"`.
final class BatteryProbe: SysProbe {
    func sample(now _: UInt64) -> Any? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return NSNull() }
        for source in sources {
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            if let description, description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                return Self.payload(description)
            }
        }
        return NSNull()
    }

    private static func payload(_ description: [String: Any]) -> [String: Any] {
        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
        let percent = maximum > 0 ? Int((Double(current) * 100 / Double(maximum)).rounded()) : 0
        let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        return [
            "percent": percent,
            "charging": description[kIOPSIsChargingKey] as? Bool ?? false,
            "source": onAC ? "ac" : "battery"
        ]
    }
}
