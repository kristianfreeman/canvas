import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An RGBA8 copy of an image, for pixel checks and golden comparisons.
struct Pixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        bytes = buffer
    }

    /// RGBA at `(x, y)`, with y down from the top.
    func pixel(_ x: Int, _ y: Int) -> [Int] {
        let start = (y * width + x) * 4
        return bytes[start..<start + 4].map(Int.init)
    }

    /// Pixels that differ from `other` by more than `tolerance` in any channel.
    func differences(from other: Self, tolerance: Int) -> Int {
        guard width == other.width, height == other.height else { return width * height }
        return bytes.withUnsafeBufferPointer { mine in
            other.bytes.withUnsafeBufferPointer { theirs in
                var count = 0
                var start = 0
                while start < mine.count {
                    var channel = 0
                    while channel < 4, abs(Int(mine[start + channel]) - Int(theirs[start + channel])) <= tolerance {
                        channel += 1
                    }
                    if channel < 4 { count += 1 }
                    start += 4
                }
                return count
            }
        }
    }

    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func write(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
