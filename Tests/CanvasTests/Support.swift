import CanvasCore
import Foundation

/// SplitMix64: a small seeded generator, so failures reproduce from the seed.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

/// Parses a JSON literal, fragments included.
func json(_ text: String) -> Any {
    guard let value = JSON.decode(Data(text.utf8)) else { fatalError("bad JSON in test: \(text)") }
    return value
}

/// A canonical encoding (sorted keys) for comparing JSON values.
func canonical(_ value: Any?) -> String {
    guard let value else { return "<absent>" }
    let options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: options),
          let text = String(bytes: data, encoding: .utf8) else { return "<invalid>" }
    return text
}

func showRequest(_ fields: [String: Any]) throws -> ShowRequest {
    var json = fields
    if json["source"] == nil { json["source"] = "" }
    return try ShowRequest(json)
}
