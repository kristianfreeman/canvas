import Darwin

/// `mach_continuous_time` in nanoseconds. The clock is shared across
/// processes and keeps counting through sleep, so the CLI and server can
/// compare timestamps.
public enum Clock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public static func now() -> UInt64 {
        nanoseconds(ticks: mach_continuous_time())
    }

    public static func nanoseconds(ticks: UInt64) -> UInt64 {
        let numer = UInt64(timebase.numer)
        let denom = UInt64(timebase.denom)
        return ticks / denom * numer + ticks % denom * numer / denom
    }

    /// Milliseconds from `start` to `end`, negative when `end` is earlier.
    public static func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        Double(Int64(bitPattern: end &- start)) / 1_000_000
    }
}
