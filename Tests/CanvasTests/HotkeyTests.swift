import CanvasCore
import Foundation
import Testing

/// A hotkey as typed, its canonical text, key code and Carbon modifier mask.
struct HotkeyCase: Sendable, CustomTestStringConvertible {
    let text: String
    let canonical: String
    let code: UInt32
    let modifiers: UInt32

    init(_ text: String, _ canonical: String, _ code: UInt32, _ modifiers: UInt32) {
        self.text = text
        self.canonical = canonical
        self.code = code
        self.modifiers = modifiers
    }

    var testDescription: String { text }
}

/// One modifier, its spellings and its Carbon bit.
struct ModifierSpelling {
    let modifier: Hotkey.Modifiers
    let names: [String]
    let carbon: UInt32
}

@Suite struct HotkeyTests {
    @Test(arguments: [
        HotkeyCase("ctrl+opt+t", "ctrl+opt+t", 17, 0x1800),
        HotkeyCase("Cmd+Shift+Space", "shift+cmd+space", 49, 0x300),
        HotkeyCase("option + control + K", "ctrl+opt+k", 40, 0x1800),
        HotkeyCase("hyper+1", "ctrl+opt+shift+cmd+1", 18, 0x1B00),
        HotkeyCase("meh+return", "ctrl+opt+shift+return", 36, 0x1A00),
        HotkeyCase("alt+enter", "opt+return", 36, 0x800),
        HotkeyCase("⌘+⇧+/", "shift+cmd+/", 44, 0x300),
        HotkeyCase("f13", "f13", 105, 0),
        HotkeyCase("ctrl+esc", "ctrl+escape", 53, 0x1000),
        HotkeyCase("cmd+-", "cmd+-", 27, 0x100),
        HotkeyCase("ctrl+←", "ctrl+left", 123, 0x1000)
    ])
    func parses(_ example: HotkeyCase) throws {
        let hotkey = try Hotkey(parsing: example.text)
        #expect(hotkey.description == example.canonical)
        #expect(hotkey.keyCode == example.code)
        #expect(hotkey.carbonModifiers == example.modifiers)
    }

    @Test(arguments: ["", "ctrl+", "+t", "t", "space", "ctrl+opt", "ctrl+nope", "super+t", "ctrl++", "f21",
                      "ctrl+tt", "ctrl+f0"])
    func rejects(text: String) {
        #expect(throws: HotkeyError.self, "\(text)") { try Hotkey(parsing: text) }
    }

    @Test func orderAndCaseDontMatter() throws {
        #expect(try Hotkey(parsing: "Opt+CTRL+T") == Hotkey(parsing: "ctrl+opt+t"))
        #expect(try Hotkey(parsing: "ctrl+t") != Hotkey(parsing: "ctrl+y"))
        #expect(try Hotkey(parsing: "ctrl+t") != Hotkey(parsing: "cmd+t"))
    }

    /// Random modifier sets, spellings, order and case. The canonical text
    /// parses back to the same hotkey, and each modifier lands in its own
    /// Carbon bit.
    @Test(arguments: 0..<300)
    func canonicalTextRoundTrips(seed: UInt64) throws {
        var rng = SeededRNG(seed: seed)
        let spellings = [
            ModifierSpelling(modifier: .control, names: ["ctrl", "control", "⌃"], carbon: 0x1000),
            ModifierSpelling(modifier: .option, names: ["opt", "option", "alt", "⌥"], carbon: 0x800),
            ModifierSpelling(modifier: .shift, names: ["shift", "⇧"], carbon: 0x200),
            ModifierSpelling(modifier: .command, names: ["cmd", "command", "⌘"], carbon: 0x100)
        ]
        let chosen = spellings.filter { _ in Bool.random(using: &rng) }
        let keys = ["a", "t", "0", "space", "f5", "left", "/", "pagedown"]
        let key = keys.randomElement(using: &rng) ?? "a"
        guard !chosen.isEmpty || key == "f5" else { return }
        var parts = chosen.map { $0.names.randomElement(using: &rng) ?? "" } + [key]
        parts = parts.map { Bool.random(using: &rng) ? $0.uppercased() : $0 }
        let modifiers = parts.dropLast().shuffled(using: &rng)
        let text = (modifiers + [parts[parts.count - 1]]).joined(separator: Bool.random(using: &rng) ? "+" : " + ")
        let hotkey = try Hotkey(parsing: text)
        #expect(try Hotkey(parsing: hotkey.description) == hotkey, "seed \(seed): \(text)")
        #expect(hotkey.carbonModifiers == chosen.reduce(0) { $0 | $1.carbon }, "seed \(seed): \(text)")
        #expect(hotkey.modifiers == Hotkey.Modifiers(chosen.map(\.modifier)), "seed \(seed): \(text)")
    }
}

@Suite struct HotkeyBindingsTests {
    private func binding(_ id: String, _ keys: String, path: String? = nil) throws -> HotkeyBinding {
        var request: [String: Any] = ["cmd": "show", "id": id, "source": "# \(id)", "kind": "markdown",
                                      "wait": true, "focus": false, "hotkey": keys, "width": 360]
        if let path { request["path"] = path }
        return HotkeyBinding(id: id, hotkey: try Hotkey(parsing: keys), request: request)
    }

    @Test func bindingReplacesTheIdsOldHotkey() throws {
        var bindings = HotkeyBindings()
        bindings.bind(try binding("todo", "ctrl+opt+t"))
        let dropped = bindings.bind(try binding("todo", "ctrl+opt+y"))
        #expect(dropped.map(\.hotkey.description) == ["ctrl+opt+t"])
        #expect(bindings.byID["todo"]?.hotkey.description == "ctrl+opt+y")
        #expect(try bindings.binding(for: Hotkey(parsing: "ctrl+opt+t")) == nil)
    }

    @Test func aHotkeyMovesToTheNewId() throws {
        var bindings = HotkeyBindings()
        bindings.bind(try binding("a", "ctrl+opt+t"))
        let dropped = bindings.bind(try binding("b", "opt+ctrl+T"))
        #expect(dropped.map(\.id) == ["a"])
        #expect(bindings.byID["a"] == nil)
        #expect(try bindings.binding(for: Hotkey(parsing: "ctrl+opt+t"))?.id == "b")
    }

    @Test func unbindRemoves() throws {
        var bindings = HotkeyBindings()
        bindings.bind(try binding("a", "ctrl+opt+t"))
        #expect(bindings.unbind("a")?.id == "a")
        #expect(bindings.unbind("a") == nil)
        #expect(bindings.byID.isEmpty)
    }

    @Test func requestsDropPerCallFields() throws {
        let request = try binding("todo", "ctrl+opt+t").request
        #expect(Set(request.keys) == ["id", "source", "kind", "width"])
    }

    @Test func showingAgainReadsTheFileAndFocuses() throws {
        let saved = try binding("todo", "ctrl+opt+t", path: "/tmp/todo.md")
        let fresh = saved.showRequest { $0 == "/tmp/todo.md" ? "# now" : nil }
        #expect(fresh["source"] as? String == "# now")
        #expect(fresh["cmd"] as? String == "show")
        #expect(fresh["focus"] as? Bool == true)
        #expect(fresh["hotkey"] == nil)
        let missing = saved.showRequest { _ in nil }
        #expect(missing["source"] as? String == "# todo")
        let request = try ShowRequest(fresh)
        #expect(request.id == "todo" && request.hotkey == nil && !request.wait)
    }

    @Test func encodesAndDecodesSkippingBadEntries() throws {
        var bindings = HotkeyBindings()
        bindings.bind(try binding("b", "ctrl+opt+b", path: "/x/b.md"))
        bindings.bind(try binding("a", "f13"))
        let data = try #require(bindings.encoded())
        let decoded = HotkeyBindings(decoding: data)
        #expect(decoded.sorted.map(\.id) == ["a", "b"])
        #expect(decoded.byID["b"]?.request["path"] as? String == "/x/b.md")
        #expect(decoded.byID["a"]?.hotkey.description == "f13")

        let messy = Data(#"[{"id":"x","hotkey":"nope","request":{}},{"id":"y"},3,"#.utf8)
            + Data(#"{"id":"z","hotkey":"cmd+z","request":{"source":""}}]"#.utf8)
        #expect(HotkeyBindings(decoding: messy).sorted.map(\.id) == ["z"])
        #expect(HotkeyBindings(decoding: Data("not json".utf8)).byID.isEmpty)
    }

    @Test func showRequestsParseHotkeys() throws {
        #expect(try showRequest(["hotkey": "ctrl+opt+t"]).hotkey == .bind(Hotkey(parsing: "ctrl+opt+t")))
        #expect(try showRequest(["hotkey": "None"]).hotkey == .unbind)
        #expect(try showRequest([:]).hotkey == nil)
        #expect(throws: RequestError.self) { try showRequest(["hotkey": "ctrl+nope"]) }
        #expect(throws: RequestError.self) { try showRequest(["hotkey": 3]) }
    }

    @Test func configReadsTheGlobalHotkey() throws {
        #expect(try Config(parsing: #"hotkey = "ctrl+opt+space""#).hotkey == Hotkey(parsing: "ctrl+opt+space"))
        #expect(Config(parsing: #"hotkey = "nope""#).hotkey == nil)
        #expect(Config(parsing: "hotkey = ctrl+t").hotkey == nil)
        #expect(Config().hotkey == nil)
    }
}

@Suite struct PanelStashTests {
    @Test func toggleAllStashesShownPanelsFirst() {
        let plan = PanelStash.toggleAll([(id: "a", state: .shown), (id: "b", state: .stashed),
                                         (id: "c", state: .shown)])
        #expect(plan.action == .stash)
        #expect(plan.ids == ["a", "c"])
    }

    @Test func toggleAllBringsBackWhenNothingIsShown() {
        let plan = PanelStash.toggleAll([(id: "a", state: .stashed), (id: "b", state: .stashed)])
        #expect(plan.action == .unstash)
        #expect(plan.ids == ["a", "b"])
        #expect(PanelStash.toggleAll([(id: String, state: PanelStash.State)]()).ids.isEmpty)
    }

    @Test func panelHotkeyFlipsTheState() {
        #expect(PanelStash.toggle(.shown) == .stash)
        #expect(PanelStash.toggle(.stashed) == .unstash)
        #expect(PanelStash.toggle(nil) == nil)
    }

    /// Random panel sets: a toggle with any panel shown leaves none shown,
    /// and a toggle with none shown leaves every panel shown.
    @Test(arguments: 0..<200)
    func toggleAllFlipsTheWholeSet(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        var states = (0..<Int.random(in: 0...6, using: &rng)).map { index in
            (id: index, state: Bool.random(using: &rng) ? PanelStash.State.shown : .stashed)
        }
        for _ in 0..<3 {
            let anyShown = states.contains { $0.state == .shown }
            let plan = PanelStash.toggleAll(states)
            states = states.map { panel in
                guard plan.ids.contains(panel.id) else { return panel }
                return (panel.id, plan.action == .stash ? .stashed : .shown)
            }
            let expected: PanelStash.State = anyShown ? .stashed : .shown
            #expect(states.allSatisfy { $0.state == expected }, "seed \(seed)")
        }
    }
}

@Suite struct ChannelPersistenceTests {
    @Test func persistMarksTheChannelForSaving() throws {
        let store = ChannelStore()
        try store.publish(ChannelMessage(channel: "plain", value: 1))
        try store.publish(ChannelMessage(channel: "todo.items", value: json(#"[{"text":"a"}]"#), persist: true))
        try store.publish(ChannelMessage(channel: "todo.items", value: json(#"[{"text":"b"}]"#)))
        #expect(store.isPersisted("todo.items"))
        #expect(!store.isPersisted("plain"))
        #expect(canonical(store.persistedValues) == #"{"todo.items":[{"text":"b"}]}"#)
    }

    @Test func restorePutsValuesBackAsPersisted() throws {
        let store = ChannelStore()
        store.restore(["todo.items": [1, 2], "Bad Name": 1, "canvas.sys.cpu": 3])
        #expect(canonical(store.latest("todo.items")) == "[1,2]")
        #expect(canonical(store.history("todo.items")) == "[[1,2]]")
        #expect(store.isPersisted("todo.items"))
        #expect(store.latest("canvas.sys.cpu") == nil)
        #expect(canonical(store.persistedValues) == #"{"todo.items":[1,2]}"#)
    }

    @Test func clearRemovesValueHistoryAndPersistence() throws {
        let store = ChannelStore()
        var heard = 0
        _ = try store.subscribe("todo.items") { _ in heard += 1 }
        try store.publish(ChannelMessage(channel: "todo.items", value: 1, persist: true))
        try store.publish(ChannelMessage(channel: "todo.items", value: NSNull(), op: .clear))
        #expect(store.latest("todo.items") == nil)
        #expect(store.history("todo.items").isEmpty)
        #expect(!store.isPersisted("todo.items"))
        #expect(heard == 1)
    }

    @Test func pubRequestsCarryPersistAndClear() throws {
        let persisted = try PubRequest(["channel": "a", "value": 1, "persist": true])
        #expect(persisted.message(1).persist)
        #expect(try !PubRequest(["channel": "a", "value": 1]).message(1).persist)
        let clear = try PubRequest(["channel": "a", "op": "clear"])
        #expect(clear.op == .clear)
        #expect(throws: ChannelError.self) { try PubRequest(["channel": "a", "op": "clear", "value": 1]) }
        #expect(throws: ChannelError.self) { try PubRequest(["channel": "a", "op": "clear", "stream": true]) }
        #expect(throws: ChannelError.self) { try PubRequest(["channel": "a"]) }
    }
}
