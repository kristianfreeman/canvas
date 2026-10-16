import CanvasCore
import Testing

@Suite struct SysDemandTests {
    @Test func nothingSubscribedMeansNoInterval() {
        let demand = SysDemand<String>()
        #expect(demand.interval == nil)
        #expect(demand.channels.isEmpty)
    }

    @Test func theSmallestRequestWinsAndADefaultCountsAsOneSecond() {
        var demand = SysDemand<String>()
        demand.add("page", .cpu, every: 2_000)
        #expect(demand.interval == 2_000)
        demand.add("cli", .procs)
        #expect(demand.interval == 1_000)
        demand.add("other", .memory, every: 250)
        #expect(demand.interval == 250)
        #expect(demand.channels == [.cpu, .procs, .memory])
    }

    @Test func intervalsBelowTheFloorAreClamped() {
        var demand = SysDemand<String>()
        demand.add("page", .net, every: 16)
        #expect(demand.interval == 100)
        demand.add("page", .net, every: 0)
        #expect(demand.interval == 100)
    }

    @Test func askingAgainReplacesThatSubscribersInterval() {
        var demand = SysDemand<String>()
        demand.add("page", .cpu, every: 500)
        demand.add("page", .cpu, every: 3_000)
        #expect(demand.interval == 3_000)
    }

    @Test func leavingRaisesTheIntervalAndTheLastToLeaveStopsIt() {
        var demand = SysDemand<String>()
        demand.add("fast", .cpu, every: 200)
        demand.add("slow", .cpu, every: 5_000)
        demand.add("slow", .disk, every: 5_000)
        demand.remove("fast", .cpu)
        #expect(demand.interval == 5_000)
        #expect(demand.channels == [.cpu, .disk])
        demand.remove("slow", .cpu)
        #expect(demand.channels == [.disk])
        demand.removeAll("slow")
        #expect(demand.interval == nil)
        #expect(demand.channels.isEmpty)
    }

    @Test func removingOneSubscriberKeepsTheOthers() {
        var demand = SysDemand<Int>()
        demand.add(1, .battery, every: 400)
        demand.add(2, .battery, every: 900)
        demand.add(1, .thermal, every: 300)
        demand.removeAll(1)
        #expect(demand.channels == [.battery])
        #expect(demand.interval == 900)
        demand.remove(3, .battery)
        #expect(demand.interval == 900)
    }

    @Test func everySystemChannelIsReservedAndValid() {
        for channel in SysChannel.allCases {
            #expect(channel.rawValue.hasPrefix(SysChannel.prefix))
            #expect(ChannelStore.isValidName(channel.rawValue))
            #expect(ChannelStore.isReserved(channel.rawValue))
        }
    }
}
