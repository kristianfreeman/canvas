import Foundation

/// JSON Merge Patch (RFC 7386) over `JSONSerialization` values.
public enum MergePatch {
    /// `patch` applied to `target`. A nil target is treated as absent.
    public static func apply(_ patch: Any, to target: Any?) -> Any {
        guard let changes = patch as? [String: Any] else { return patch }
        var result = target as? [String: Any] ?? [:]
        for (key, value) in changes {
            if value is NSNull {
                result[key] = nil
            } else {
                result[key] = apply(value, to: result[key])
            }
        }
        return result
    }
}
