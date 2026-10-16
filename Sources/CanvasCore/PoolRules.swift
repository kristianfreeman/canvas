/// How a pool of parked panel hosts behaves: whether it loads a host before
/// anyone asks, keeps a closed panel's host, and when it drops the parked one.
public struct PoolRules: Equatable {
    public let prefills: Bool
    public let keepsHost: Bool
    private let trimAfter: Double?

    /// The WebKit fallback, by the `warm` policy. Only web panels count as
    /// open: native panels don't need a page.
    public static func web(_ policy: WarmPolicy) -> Self {
        Self(prefills: policy.prefills, keepsHost: policy.keepsPage, trimAfter: policy.trimDelay(visiblePanels: 0))
    }

    /// Native hosts are cheap: one stays parked from launch, always.
    public static let native = Self(prefills: true, keepsHost: true, trimAfter: nil)

    /// Seconds before the parked host is dropped, given how many of this
    /// pool's kind of panel are open, or nil to keep it.
    public func trimDelay(openPanels: Int) -> Double? {
        openPanels == 0 ? trimAfter : nil
    }
}
