@testable import CanvasCore
import Foundation
import Testing

@Suite struct RouteCacheTests {
    @Test func unknownContentGoesNativeFirst() {
        var cache = RouteCache()
        #expect(cache.route(path: "/tmp/a.tsx", source: "x") == .native)
        #expect(cache.route(path: nil, source: "x") == .native)
    }

    @Test func contentThatNeededWebGoesStraightThere() {
        var cache = RouteCache()
        cache.record(.web, path: "/tmp/a.tsx", source: "<div/>")
        #expect(cache.route(path: "/tmp/a.tsx", source: "<div/>") == .web)
        #expect(cache.route(path: "/tmp/b.tsx", source: "<div/>") == .native)
    }

    @Test func anEditedFileIsTriedNativelyAgain() {
        var cache = RouteCache()
        cache.record(.web, path: "/tmp/a.tsx", source: "<div/>")
        #expect(cache.route(path: "/tmp/a.tsx", source: "<Text/>") == .native)
        cache.record(.native, path: "/tmp/a.tsx", source: "<Text/>")
        #expect(cache.route(path: "/tmp/a.tsx", source: "<div/>") == .native)
        #expect(cache.isEmpty)
    }

    @Test func aWebEntryFollowsTheLatestVersionOfAPath() {
        var cache = RouteCache()
        cache.record(.web, path: "/tmp/a.tsx", source: "one")
        cache.record(.web, path: "/tmp/a.tsx", source: "two")
        #expect(cache.count == 1)
        #expect(cache.route(path: "/tmp/a.tsx", source: "one") == .native)
        #expect(cache.route(path: "/tmp/a.tsx", source: "two") == .web)
    }

    @Test func stdinIsKeyedByItsSource() {
        var cache = RouteCache()
        cache.record(.web, path: nil, source: "<div/>")
        #expect(cache.route(path: nil, source: "<div/>") == .web)
        #expect(cache.route(path: "", source: "<div/>") == .web)
        #expect(cache.route(path: nil, source: "<div />") == .native)
        #expect(cache.route(path: "/tmp/a.tsx", source: "<div/>") == .native)
    }

    @Test func theLeastRecentlyUsedEntryGoesFirst() {
        var cache = RouteCache(capacity: 2)
        cache.record(.web, path: "/a", source: "a")
        cache.record(.web, path: "/b", source: "b")
        #expect(cache.route(path: "/a", source: "a") == .web)
        cache.record(.web, path: "/c", source: "c")
        #expect(cache.count == 2)
        #expect(cache.route(path: "/b", source: "b") == .native)
        #expect(cache.route(path: "/a", source: "a") == .web)
        #expect(cache.route(path: "/c", source: "c") == .web)
    }

    @Test func theHashIsStableAcrossRuns() {
        #expect(RouteCache.fnv1a("") == 0xcbf2_9ce4_8422_2325)
        #expect(RouteCache.fnv1a("a") == 0xaf63_dc4c_8601_ec8c)
    }

    @Test func routeStepSwapsOnlyWhenTheRendererDiffers() {
        #expect(RouteStep.step(current: .native, wanted: .native) == .stay)
        #expect(RouteStep.step(current: .web, wanted: .web) == .stay)
        #expect(RouteStep.step(current: .native, wanted: .web) == .swap(to: .web))
        #expect(RouteStep.step(current: .web, wanted: .native) == .swap(to: .native))
    }

    /// Random records and lookups against a plain LRU model.
    @Test(arguments: [UInt64(1), 7, 42, 2026, 0xC0FFEE])
    func matchesAnLRUModel(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        var cache = RouteCache(capacity: 4)
        var model: [(key: String, source: String)] = []
        for step in 0..<400 {
            let path = Bool.random(using: &rng) ? "/f\(Int.random(in: 0..<7, using: &rng))" : nil
            let source = "s\(Int.random(in: 0..<3, using: &rng))"
            let key = path ?? "#" + source
            let index = model.firstIndex { $0.key == key }
            if Int.random(in: 0..<3, using: &rng) == 0 {
                let renderer: Renderer = Bool.random(using: &rng) ? .web : .native
                cache.record(renderer, path: path, source: source)
                if let index { model.remove(at: index) }
                if renderer == .web { model.append((key, source)) }
                if model.count > 4 { model.removeFirst() }
            } else {
                let hit = index.map { model[$0].source == source } ?? false
                if let index, hit { model.append(model.remove(at: index)) }
                #expect(cache.route(path: path, source: source) == (hit ? .web : .native), "seed \(seed) step \(step)")
            }
            #expect(cache.count == model.count, "seed \(seed) step \(step)")
        }
    }
}

@Suite struct PoolRulesTests {
    @Test func theWebPoolLingersOnlyWithNoWebPanelOpen() {
        let rules = PoolRules.web(WarmPolicy(Config()))
        #expect(!rules.prefills)
        #expect(rules.keepsHost)
        #expect(rules.trimDelay(openPanels: 0) == 120)
        #expect(rules.trimDelay(openPanels: 1) == nil)
    }

    @Test func theWebPoolFollowsTheWarmSetting() {
        let always = PoolRules.web(WarmPolicy(Config(parsing: #"warm = "always""#)))
        #expect(always.prefills && always.trimDelay(openPanels: 0) == nil)
        let never = PoolRules.web(WarmPolicy(Config(parsing: #"warm = "never""#)))
        #expect(!never.prefills && !never.keepsHost)
        let idle = PoolRules.web(WarmPolicy(Config(parsing: "warm = \"idle\"\nidle_minutes = 2")))
        #expect(idle.prefills && idle.trimDelay(openPanels: 0) == 120)
    }

    @Test func oneNativeHostStaysParkedWhatever() {
        let rules = PoolRules.native
        #expect(rules.prefills && rules.keepsHost)
        #expect(rules.trimDelay(openPanels: 0) == nil)
        #expect(rules.trimDelay(openPanels: 3) == nil)
    }
}
