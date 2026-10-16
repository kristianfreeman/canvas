import CanvasCore
import Testing

private func ticks(_ user: UInt32, _ system: UInt32, _ idle: UInt32, nice: UInt32 = 0) -> CPUTicks {
    CPUTicks(user: user, system: system, idle: idle, nice: nice)
}

@Suite struct CPULoadTests {
    @Test func busyShareIsUserSystemAndNiceOverAllTicks() throws {
        let before = [ticks(100, 50, 850), ticks(10, 10, 80, nice: 0)]
        let after = [ticks(200, 100, 1050), ticks(30, 10, 100, nice: 20)]
        let usage = try #require(CPULoad.usage(from: before, to: after))
        // Core 0: 150 busy of 350. Core 1: 40 busy (20 user + 20 nice) of 60.
        #expect(abs(usage.cores[0] - 150.0 / 350) < 1e-12)
        #expect(abs(usage.cores[1] - 40.0 / 60) < 1e-12)
        // The total weighs cores by their ticks, not an average of fractions.
        #expect(abs(usage.total - 190.0 / 410) < 1e-12)
    }

    @Test func countersThatWrapStillGiveTheTrueDelta() throws {
        let before = [ticks(UInt32.max - 9, 0, UInt32.max - 59)]
        let after = [ticks(30, 0, 0)]
        let usage = try #require(CPULoad.usage(from: before, to: after))
        // 40 busy ticks across the wrap, 60 idle.
        #expect(abs(usage.total - 0.4) < 1e-12)
        #expect(usage.cores.count == 1)
    }

    @Test func noTicksBetweenReadingsIsIdleNotNaN() throws {
        let same = [ticks(5, 5, 5), ticks(1, 2, 3)]
        let usage = try #require(CPULoad.usage(from: same, to: same))
        #expect(usage == CPUUsage(total: 0, cores: [0, 0]))
    }

    @Test func aChangedCoreCountOrNoCoresGivesNothing() {
        #expect(CPULoad.usage(from: [ticks(1, 1, 1)], to: [ticks(2, 2, 2), ticks(2, 2, 2)]) == nil)
        #expect(CPULoad.usage(from: [], to: []) == nil)
    }
}

@Suite struct CounterTests {
    @Test func aRisingCounterMovesByTheDifference() {
        #expect(Counter.delta(from: 1_000, to: 4_500) == 3_500)
        #expect(Counter.delta(from: 7, to: 7) == 0)
    }

    @Test func a32BitCounterNearTheTopWraps() {
        let previous: UInt64 = 4_294_967_000
        #expect(Counter.delta(from: previous, to: 200, width: 32) == 296 + 200)
        #expect(Counter.delta(from: UInt64(UInt32.max), to: 0, width: 32) == 1)
    }

    @Test func aDropFarFromTheTopIsAResetAndCountsAsNothing() {
        #expect(Counter.delta(from: 1_000, to: 10, width: 32) == 0)
        #expect(Counter.delta(from: 5_000, to: 100) == 0)
        #expect(Counter.delta(from: UInt64.max - 5, to: 3) == 0)
    }

    @Test func aPreviousValueTooWideForTheCounterIsAReset() {
        #expect(Counter.delta(from: 1 << 40, to: 5, width: 32) == 0)
    }

    @Test func rateIsPerSecondOverTheMeasuredTime() {
        #expect(Counter.rate(1_500, nanoseconds: 500_000_000) == 3_000)
        #expect(Counter.rate(1_000, nanoseconds: 2_000_000_000) == 500)
        #expect(Counter.rate(1_000, nanoseconds: 0) == 0)
    }

    @Test func aWrappedCounterGivesASteadyRate() {
        let period: UInt64 = 1_000_000_000
        var counter: UInt32 = UInt32.max - 2_500_000
        var rates: [Double] = []
        for _ in 0..<4 {
            let previous = counter
            counter &+= 1_000_000
            let moved = Counter.delta(from: UInt64(previous), to: UInt64(counter), width: 32)
            rates.append(Counter.rate(moved, nanoseconds: period))
        }
        #expect(rates == [1_000_000, 1_000_000, 1_000_000, 1_000_000])
    }
}

@Suite struct TopNTests {
    private struct Item: Equatable {
        let score: Int
        let index: Int
    }

    /// Sorting everything is the obvious, slow way to the same answer.
    private func oracle(_ items: [Item], _ count: Int) -> [Item] {
        Array(items.sorted { $0.score > $1.score || ($0.score == $1.score && $0.index < $1.index) }.prefix(count))
    }

    @Test(arguments: [UInt64(1), 7, 99, 2_026])
    func matchesAFullSortWithTiesInInputOrder(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        for _ in 0..<50 {
            let length = Int.random(in: 0...200, using: &rng)
            let items = (0..<length).map { Item(score: Int.random(in: 0..<15, using: &rng), index: $0) }
            let count = Int.random(in: 0...60, using: &rng)
            #expect(TopN.select(items, count: count) { $0.score > $1.score } == oracle(items, count))
        }
    }

    @Test func fewerElementsThanCountReturnsThemAllHighestFirst() {
        #expect(TopN.select([3, 9, 1], count: 40, isHigher: >) == [9, 3, 1])
    }

    @Test func zeroCountReturnsNothing() {
        #expect(TopN.select([3, 9, 1], count: 0, isHigher: >).isEmpty)
    }
}
