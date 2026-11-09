@testable import CanvasCore
import Foundation
import Testing

/// What a run of `GlobalHotkeySwap`s leaves registered, against a model of
/// Carbon's registrations: registering keys that are taken replaces their
/// action, as `HotkeyCenter.register` does.
@Suite struct GlobalHotkeySwapTests {
    static let pool = ["ctrl+opt+a", "ctrl+opt+b", "ctrl+opt+c", "ctrl+opt+space"]
        .compactMap { try? Hotkey(parsing: $0) }

    @Test func poolParses() { #expect(Self.pool.count == 4) }

    struct Registry {
        var owners: [Hotkey: HotkeyRegistration] = [:]

        mutating func apply(_ swap: GlobalHotkeySwap) {
            swap.unregister.forEach { owners[$0] = nil }
            swap.register.forEach { owners[$0.hotkey] = $0 }
        }

        /// The global hotkey owns its keys; every other panel hotkey owns its own.
        static func expected(global: Hotkey?, bindings: HotkeyBindings) -> [Hotkey: HotkeyRegistration] {
            var owners: [Hotkey: HotkeyRegistration] = [:]
            for binding in bindings.sorted where binding.hotkey != global {
                owners[binding.hotkey] = .panel(id: binding.id, hotkey: binding.hotkey)
            }
            if let global { owners[global] = .global(global) }
            return owners
        }
    }

    static func bindings(_ pairs: [(String, Hotkey)]) -> HotkeyBindings {
        var bindings = HotkeyBindings()
        for (id, hotkey) in pairs { bindings.bind(HotkeyBinding(id: id, hotkey: hotkey, request: ["id": id])) }
        return bindings
    }

    @Test func noChangeDoesNothing() {
        let bindings = Self.bindings([("todo", Self.pool[0])])
        #expect(GlobalHotkeySwap(from: Self.pool[0], to: Self.pool[0], bindings: bindings)
            == GlobalHotkeySwap(from: nil, to: nil, bindings: bindings))
        #expect(GlobalHotkeySwap(from: nil, to: nil, bindings: bindings).register.isEmpty)
    }

    @Test func movingOffAPanelsKeysHandsThemBack() {
        let bindings = Self.bindings([("todo", Self.pool[0])])
        let swap = GlobalHotkeySwap(from: Self.pool[0], to: Self.pool[3], bindings: bindings)
        #expect(swap.unregister == [Self.pool[0]])
        #expect(swap.register == [.panel(id: "todo", hotkey: Self.pool[0]), .global(Self.pool[3])])
    }

    @Test func removingTheGlobalHotkeyUnregistersIt() {
        let swap = GlobalHotkeySwap(from: Self.pool[3], to: nil, bindings: HotkeyBindings())
        #expect(swap.unregister == [Self.pool[3]])
        #expect(swap.register.isEmpty)
    }

    /// Panel hotkeys registered at launch, then random config edits: after
    /// each one exactly the expected keys are registered, to the right owner.
    @Test(arguments: 0..<200)
    func registrationsFollowEveryEdit(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        let keys = Self.pool.shuffled(using: &rng)
        let count = Int.random(in: 0...3, using: &rng)
        let bindings = Self.bindings((0..<count).map { ("id\($0)", keys[$0]) })
        var registry = Registry()
        bindings.sorted.forEach { registry.owners[$0.hotkey] = .panel(id: $0.id, hotkey: $0.hotkey) }
        var global: Hotkey?
        for step in 0..<8 {
            let next = Bool.random(using: &rng) ? nil : Self.pool.randomElement(using: &rng)
            registry.apply(GlobalHotkeySwap(from: global, to: next, bindings: bindings))
            global = next
            #expect(registry.owners == Registry.expected(global: global, bindings: bindings),
                    "seed \(seed), step \(step), global \(global?.description ?? "none")")
        }
    }
}

@Suite struct ConfigWatchTests {
    @Test func watchesTheFilesFolderWhenItExists() {
        let file = URL(fileURLWithPath: "/home/me/.config/canvas/config.toml")
        #expect(ConfigWatch.nearestFolder(of: file) { _ in true }.path == "/home/me/.config/canvas")
    }

    @Test func climbsToTheNearestFolderThatExists() {
        let file = URL(fileURLWithPath: "/home/me/.config/canvas/config.toml")
        let existing: Set = ["/home/me", "/home", "/"]
        #expect(ConfigWatch.nearestFolder(of: file) { existing.contains($0) }.path == "/home/me")
    }

    @Test func stopsAtTheRoot() {
        let file = URL(fileURLWithPath: "/a/b/config.toml")
        #expect(ConfigWatch.nearestFolder(of: file) { _ in false }.path == "/")
    }
}
