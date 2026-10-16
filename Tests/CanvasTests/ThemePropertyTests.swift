import CanvasCore
import Foundation
import Testing

/// Seeded random colors through every syntax `CSSColor` reads. Each
/// property runs 500 seeds; a failure names its seed.
@Suite struct ThemePropertyTests {
    static func bytes(_ rng: inout SeededRNG) -> [Int] {
        (0..<4).map { _ in Int.random(in: 0...255, using: &rng) }
    }

    static func color(_ bytes: [Int]) -> RGBA {
        RGBA(red: Double(bytes[0]) / 255, green: Double(bytes[1]) / 255, blue: Double(bytes[2]) / 255,
             alpha: Double(bytes[3]) / 255)
    }

    @Test(arguments: 0..<500)
    func hexRoundTrips(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        let color = Self.color(Self.bytes(&rng))
        #expect(CSSColor.parse(color.hex) == color, "seed \(seed): \(color.hex)")
        #expect(CSSColor.parse(color.hex.uppercased()) == color, "seed \(seed)")
    }

    @Test(arguments: 0..<500)
    func rgbFunctionsMatchHex(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        let bytes = Self.bytes(&rng)
        let alpha = Double(bytes[3]) / 255
        let comma = "rgba(\(bytes[0]), \(bytes[1]), \(bytes[2]), \(alpha))"
        let space = "rgb(\(bytes[0]) \(bytes[1]) \(bytes[2]) / \(alpha * 100)%)"
        let expected = Self.color(bytes).hex
        #expect(CSSColor.parse(comma)?.hex == expected, "seed \(seed): \(comma)")
        #expect(CSSColor.parse(space)?.hex == expected, "seed \(seed): \(space)")
    }

    /// Mixing stays in range and its endpoints are the inputs.
    @Test(arguments: 0..<500)
    func mixEndpoints(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        let first = Self.color(Self.bytes(&rng))
        let second = Self.color(Self.bytes(&rng))
        let share = Double.random(in: 0...1, using: &rng)
        let mixed = first.mixed(share, with: second)
        for channel in [mixed.red, mixed.green, mixed.blue, mixed.alpha] {
            #expect((0...1).contains(channel), "seed \(seed)")
        }
        #expect(first.mixed(1, with: second).hex == first.hex || first.alpha == 0, "seed \(seed)")
        #expect(first.mixed(0, with: second).hex == second.hex || second.alpha == 0, "seed \(seed)")
    }
}
