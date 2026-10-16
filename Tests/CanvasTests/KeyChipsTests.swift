import CanvasCore
import Foundation
import Testing

@Suite struct KeyChipsTests {
    @Test(arguments: [
        ("Hyper 1–7", [KeyChip.hyper, .key("1–7")]),
        ("Hyper Tab", [.hyper, .key("Tab")]),
        ("Hyper H J K L", [.hyper, .key("H"), .key("J"), .key("K"), .key("L")]),
        ("Hyper ← ↑ ↓ →", [.hyper, .key("←"), .key("↑"), .key("↓"), .key("→")]),
        ("Hyper - =", [.hyper, .key("-"), .key("=")]),
        ("Hyper `", [.hyper, .key("`")]),
        ("Caps Lock tap", [.key("Caps Lock"), .note("tap")]),
        ("Hyper W → 1–7", [.hyper, .key("W"), .then, .key("1–7")]),
        ("Hyper W → Arrows", [.hyper, .key("W"), .then, .key("Arrows")]),
        ("Hyper W → Esc", [.hyper, .key("W"), .then, .key("Esc")])
    ])
    func keysJSONRows(keys: String, chips: [KeyChip]) {
        #expect(KeyChips.parse(keys) == chips)
    }

    @Test func separatorNeedsNonArrowNeighbours() {
        #expect(KeyChips.parse("← →") == [.key("←"), .key("→")])
        #expect(KeyChips.parse("→ W") == [.key("→"), .key("W")])
        #expect(KeyChips.parse("W → ↓") == [.key("W"), .key("→"), .key("↓")])
        #expect(KeyChips.parse("A → B → C") == [.key("A"), .then, .key("B"), .then, .key("C")])
    }

    @Test func notesPlusAndCase() {
        #expect(KeyChips.parse("Cmd + K") == [.key("Cmd"), .plus, .key("K")])
        #expect(KeyChips.parse("hyper E Again") == [.hyper, .key("E"), .note("Again")])
        #expect(KeyChips.parse("Esc or Q") == [.key("Esc"), .note("or"), .key("Q")])
        #expect(KeyChips.parse("Space hold") == [.key("Space"), .note("hold")])
        #expect(KeyChips.parse("caps lock twice") == [.key("Caps Lock"), .note("twice")])
        #expect(KeyChips.parse("  Page   Down  then  Num Lock ")
            == [.key("Page Down"), .note("then"), .key("Num Lock")])
        #expect(KeyChips.parse("Caps") == [.key("Caps")])
        #expect(KeyChips.parse("") == [])
    }

    @Test func arraysAreTokensAsGiven() {
        let value = JSONValue(["Hyper", "Caps Lock", "→", "1", 7, "tap"] as [Any])
        #expect(KeyChips.parse(value) == [.hyper, .key("Caps Lock"), .then, .key("1"), .note("tap")])
        #expect(KeyChips.parse(JSONValue("Hyper W")) == [.hyper, .key("W")])
        #expect(KeyChips.parse(nil) == [])
        #expect(KeyChips.parse(JSONValue(3)) == [])
    }

    /// Every row of the real cheat sheet parses, and rows that start with
    /// Hyper start with the Hyper chip.
    @Test func everyRowOfKeysJSON() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../examples/keys.json")
        let data = JSONValue(try JSONSerialization.jsonObject(with: Data(contentsOf: url)))
        let rows = (data["groups"]?.array ?? []).flatMap { $0["rows"]?.array ?? [] }
        #expect(rows.count > 20)
        for row in rows {
            let keys = try #require(row["keys"]?.string)
            let chips = KeyChips.parse(keys)
            #expect(!chips.isEmpty, "\(keys)")
            #expect(keys.hasPrefix("Hyper") == (chips.first == .hyper), "\(keys)")
            #expect(!chips.contains(.plus), "\(keys)")
        }
    }
}
