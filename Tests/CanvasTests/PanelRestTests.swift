import CanvasCore
import Foundation
import Testing

@Suite struct PanelRestTests {
    private static let base: [String: Any] = [
        "id": "cheatsheet", "kind": "tsx", "source": "export default () => null", "path": "/k.tsx",
        "title": "Shortcuts", "data": ["groups": [["name": "A", "rows": [["keys": "Hyper I"]]]]], "width": 900
    ]

    private func request(_ changes: [String: Any] = [:]) throws -> ShowRequest {
        try showRequest(Self.base.merging(changes) { $1 })
    }

    @Test func aWaitingOrStreamingPanelDoesNotRest() throws {
        #expect(PanelRest.mayRest(try request()))
        #expect(!PanelRest.mayRest(try request(["wait": true])))
        #expect(!PanelRest.mayRest(try request(["stream": true])))
    }

    @Test func theSameRequestMatchesEvenWithDifferentFocusOrTrace() throws {
        #expect(PanelRest.sameShow(try request(), try request()))
        #expect(PanelRest.sameShow(try request(), try request(["focus": true, "trace": true])))
        let reordered = try request(["data": ["groups": [["rows": [["keys": "Hyper I"]], "name": "A"]]]])
        #expect(PanelRest.sameShow(try request(), reordered))
    }

    @Test(arguments: [
        ("source", "export default () => 1" as Any), ("path", "/other.tsx"), ("title", "Keys"),
        ("kind", "markdown"), ("data", ["groups": []]), ("buttons", ["OK"]), ("accent", "red"),
        ("theme", "light"), ("width", 600), ("position", "top-left"), ("pin", true), ("wait", true)
    ])
    func anyChangeToWhatOrWhereItDrawsDoesNotMatch(field: String, value: Any) throws {
        #expect(!PanelRest.sameShow(try request(), try request([field: value])), "\(field) changed")
    }

    @Test func missingDataMatchesOnlyMissingData() throws {
        let bare = try request(["data": NSNull()])
        #expect(PanelRest.sameShow(bare, bare))
        #expect(!PanelRest.sameShow(bare, try request()))
    }

    @Test func theShelfPushesOutTheSameIdThenTheLongestResting() {
        var shelf = RestShelf<Int>(capacity: 2)
        #expect(shelf.put("a", 1).isEmpty)
        #expect(shelf.put("b", 2).isEmpty)
        #expect(shelf.put("a", 3) == [1])
        #expect(shelf.put("c", 4) == [2])
        #expect(shelf.take("b") == nil)
        #expect(shelf.take("a") == 3)
        #expect(shelf.removeAll() == [4])
        #expect(shelf.isEmpty)
    }

    /// Random puts and takes against a plain list model; nothing is lost or kept twice.
    @Test(arguments: [UInt64(3), 11, 64, 2026, 0xBEEF])
    func theShelfMatchesAListModel(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        var shelf = RestShelf<Int>(capacity: 3)
        var model: [(id: String, value: Int)] = []
        for step in 0..<400 {
            let id = "p\(Int.random(in: 0..<6, using: &rng))"
            if Bool.random(using: &rng) {
                var expected: [Int] = []
                if let index = model.firstIndex(where: { $0.id == id }) {
                    expected.append(model.remove(at: index).value)
                }
                model.append((id, step))
                while model.count > 3 { expected.append(model.removeFirst().value) }
                #expect(shelf.put(id, step) == expected, "seed \(seed) step \(step)")
            } else {
                let index = model.firstIndex { $0.id == id }
                #expect(shelf.take(id) == index.map { model.remove(at: $0).value }, "seed \(seed) step \(step)")
            }
            #expect(shelf.count == model.count, "seed \(seed) step \(step)")
        }
    }
}
