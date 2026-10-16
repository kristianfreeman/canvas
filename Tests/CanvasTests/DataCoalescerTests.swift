import CanvasCore
import Testing

@Suite struct DataCoalescerTests {
    private let frame = DataCoalescer<Int>.frameInterval

    @Test func firstOfferFlushesImmediately() {
        var coalescer = DataCoalescer<Int>()
        #expect(coalescer.offer(1, now: 1_000) == 0)
        #expect(coalescer.flush(now: 1_000) == 1)
        #expect(!coalescer.hasPending)
    }

    @Test func offersWhileScheduledAskForNoNewFlush() {
        var coalescer = DataCoalescer<Int>()
        #expect(coalescer.offer(1, now: 0) == 0)
        #expect(coalescer.offer(2, now: 10) == nil)
        #expect(coalescer.offer(3, now: 20) == nil)
        #expect(coalescer.flush(now: 30) == 3)
    }

    @Test func nextFlushWaitsOutTheRestOfTheFrame() {
        var coalescer = DataCoalescer<Int>()
        _ = coalescer.offer(1, now: 0)
        _ = coalescer.flush(now: 1_000_000)
        #expect(coalescer.offer(2, now: 5_000_000) == frame - 4_000_000)
        #expect(coalescer.flush(now: 1_000_000 + frame) == 2)
    }

    @Test func offerAfterAQuietFrameFlushesImmediately() {
        var coalescer = DataCoalescer<Int>()
        _ = coalescer.offer(1, now: 0)
        _ = coalescer.flush(now: 0)
        #expect(coalescer.offer(2, now: frame) == 0)
        #expect(coalescer.offer(3, now: frame * 10) == nil)
    }

    @Test func flushWithNothingPendingReturnsNilAndUnschedules() {
        var coalescer = DataCoalescer<Int>()
        _ = coalescer.offer(1, now: 0)
        _ = coalescer.flush(now: 0)
        #expect(coalescer.flush(now: 1) == nil)
        #expect(coalescer.offer(2, now: frame * 2) == 0)
    }

    /// However values arrive, flushes are at least one interval apart and the
    /// last flush delivers the last value offered.
    @Test(arguments: [UInt64(1), 2, 3, 42, 1_234])
    func flushesAreSpacedAndLatestWins(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        var coalescer = DataCoalescer<Int>()
        var now: UInt64 = 0
        var due: UInt64?
        var flushes: [UInt64] = []
        var delivered: Int?
        for value in 0..<500 {
            now += UInt64.random(in: 0...(frame / 2), using: &rng)
            if let at = due, at <= now {
                if let flushed = coalescer.flush(now: at) { delivered = flushed }
                flushes.append(at)
                due = nil
            }
            if let delay = coalescer.offer(value, now: now) { due = now + delay }
        }
        if let at = due, let flushed = coalescer.flush(now: at) {
            delivered = flushed
            flushes.append(at)
        }
        #expect(delivered == 499)
        for (earlier, later) in zip(flushes, flushes.dropFirst()) {
            #expect(later - earlier >= frame)
        }
    }
}
