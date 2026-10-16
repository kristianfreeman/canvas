import CoreGraphics
import Foundation
import Testing
import TestSupport

/// Compares an offscreen render with its PNG under Tests/golden/native.
/// `UPDATE_GOLDENS=1` rewrites the PNG; a mismatch leaves the actual image
/// in .build/native-goldens.
enum Golden {
    static let root = Repo.root.appendingPathComponent("Tests/golden/native", isDirectory: true)
    static let failures = Repo.root.appendingPathComponent(".build/native-goldens", isDirectory: true)
    static let updating = ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1"
    /// Channel difference a pixel may have, and the share of pixels that may exceed it.
    static let tolerance = 8
    static let allowedShare = 0.001

    /// `file` is relative to Tests/golden/native, like `examples/top-dark.png`.
    static func check(_ image: CGImage, _ file: String) throws {
        let golden = root.appendingPathComponent(file)
        if updating {
            try Pixels.write(image, to: golden)
            return
        }
        let expected = try #require(Pixels.load(golden).flatMap(Pixels.init),
                                    "no golden \(file); run with UPDATE_GOLDENS=1")
        let actual = try #require(Pixels(image))
        let differing = actual.differences(from: expected, tolerance: tolerance)
        let limit = Int(Double(expected.width * expected.height) * allowedShare)
        if differing > limit || actual.height != expected.height {
            try Pixels.write(image, to: failures.appendingPathComponent(file))
        }
        #expect(actual.width == expected.width && actual.height == expected.height,
                "\(file): \(actual.width)×\(actual.height), golden \(expected.width)×\(expected.height)")
        #expect(differing <= limit, "\(file): \(differing) pixels differ (limit \(limit))")
    }
}
