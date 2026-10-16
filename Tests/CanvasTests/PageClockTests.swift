import CanvasCore
import Testing

@Suite struct PageClockTests {
    private let sample = PageClock(wallMilliseconds: 1_000_000, clockNanoseconds: 50_000_000)

    @Test func pageTimeMapsByItsOffsetFromTheSample() {
        let mapped = sample.clock(pageMilliseconds: 1_000_002.5, within: 0...UInt64.max)
        #expect(mapped == 52_500_000)
    }

    @Test func mappedTimeIsClampedToTheBounds() {
        #expect(sample.clock(pageMilliseconds: 999_000, within: 40_000_000...60_000_000) == 40_000_000)
        #expect(sample.clock(pageMilliseconds: 1_001_000, within: 40_000_000...60_000_000) == 60_000_000)
    }

    @Test func nonFiniteTimeFallsBackToTheLowerBound() {
        #expect(sample.clock(pageMilliseconds: .nan, within: 7...9) == 7)
        #expect(sample.clock(pageMilliseconds: .infinity, within: 7...9) == 7)
    }

    @Test func averageIsTheMidpointOfBothClocks() {
        let later = PageClock(wallMilliseconds: 1_000_010, clockNanoseconds: 60_000_000)
        let mid = PageClock.average(sample, later)
        #expect(mid.wallMilliseconds == 1_000_005)
        #expect(mid.clockNanoseconds == 55_000_000)
    }

    @Test func windowPlacesPageStampsBetweenItsSamples() {
        let after = PageClock(wallMilliseconds: 1_000_004, clockNanoseconds: 54_000_000)
        let window = PageClock.Window(sample, after)
        #expect(window.clock(pageMilliseconds: 1_000_001) == 51_000_000)
        #expect(window.clock(pageMilliseconds: 999_000) == 50_000_000)
        #expect(window.clock(pageMilliseconds: 2_000_000) == 54_000_000)
    }

    @Test func liveSampleTracksTheMonotonicClock() {
        let before = Clock.now()
        let live = PageClock.sample()
        let after = Clock.now()
        #expect((before...after).contains(live.clockNanoseconds))
    }
}
