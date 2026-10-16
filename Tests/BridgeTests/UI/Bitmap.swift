import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An image as 8-bit premultiplied sRGB RGBA, for comparing snapshots.
struct Bitmap {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        pixels = bytes
    }

    init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.init(image)
    }

    var image: CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    func writePNG(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let image,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Compares `size`×`size` block averages, so text antialiasing that
    /// shifts between runs cancels out while moved or recolored elements
    /// don't. Counts blocks where any channel's average differs by more
    /// than `tolerance`; a size mismatch makes every block differ.
    func differingBlocks(from other: Self, size: Int, tolerance: Int) -> (differing: Int, total: Int) {
        let columns = width / size
        let rows = height / size
        guard width == other.width, height == other.height else { return (columns * rows, columns * rows) }
        let limit = tolerance * size * size
        var differing = 0
        for row in 0..<rows {
            for column in 0..<columns {
                let mine = blockSums(column, row, size: size)
                let theirs = other.blockSums(column, row, size: size)
                if zip(mine, theirs).contains(where: { abs($0 - $1) > limit }) { differing += 1 }
            }
        }
        return (differing, columns * rows)
    }

    private func blockSums(_ column: Int, _ row: Int, size: Int) -> [Int] {
        var sums = [Int](repeating: 0, count: 4)
        for y in row * size..<(row + 1) * size {
            for x in column * size..<(column + 1) * size {
                let start = (y * width + x) * 4
                for channel in 0..<4 { sums[channel] += Int(pixels[start + channel]) }
            }
        }
        return sums
    }
}
