import Foundation

/// Maps the page's clock (`performance.timeOrigin + performance.now()`,
/// milliseconds since the Unix epoch) onto `Clock` nanoseconds, from a
/// sample of both clocks taken at the same moment.
public struct PageClock {
    public let wallMilliseconds: Double
    public let clockNanoseconds: UInt64

    public init(wallMilliseconds: Double, clockNanoseconds: UInt64) {
        self.wallMilliseconds = wallMilliseconds
        self.clockNanoseconds = clockNanoseconds
    }

    /// Samples the wall clock between two reads of `Clock` and uses their
    /// midpoint.
    public static func sample() -> Self {
        let before = Clock.now()
        let wall = Date().timeIntervalSince1970 * 1000
        let after = Clock.now()
        return Self(wallMilliseconds: wall, clockNanoseconds: before + (after - before) / 2)
    }

    /// The averaged sample of two taken around a call.
    public static func average(_ first: Self, _ second: Self) -> Self {
        Self(
            wallMilliseconds: (first.wallMilliseconds + second.wallMilliseconds) / 2,
            clockNanoseconds: first.clockNanoseconds / 2 + second.clockNanoseconds / 2)
    }

    /// `pageMilliseconds` on the `Clock`, clamped to `bounds` since both
    /// stamps were taken while the call was in flight.
    public func clock(pageMilliseconds: Double, within bounds: ClosedRange<UInt64>) -> UInt64 {
        let offset = (pageMilliseconds - wallMilliseconds) * 1_000_000
        let mapped = Double(clockNanoseconds) + offset
        guard mapped.isFinite else { return bounds.lowerBound }
        let clamped = min(max(mapped, Double(bounds.lowerBound)), Double(bounds.upperBound))
        return UInt64(clamped)
    }

    /// Samples taken just before and just after a call into the page, so
    /// stamps the page took during the call land between them.
    public struct Window {
        public let before: PageClock
        public let after: PageClock

        public init(_ before: PageClock, _ after: PageClock) {
            self.before = before
            self.after = after
        }

        public func clock(pageMilliseconds: Double) -> UInt64 {
            let low = min(before.clockNanoseconds, after.clockNanoseconds)
            let high = max(before.clockNanoseconds, after.clockNanoseconds)
            return PageClock.average(before, after).clock(pageMilliseconds: pageMilliseconds, within: low...high)
        }
    }
}
