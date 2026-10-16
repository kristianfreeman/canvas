import Foundation

/// A frame the user dragged or resized a panel to. The anchor is the nearer
/// edge on each axis, so a restored panel whose content is a different
/// height keeps the edge the user put it against.
public struct RememberedFrame: Equatable, Codable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat
    public var anchor: Anchor

    public init(frame: CGRect, anchor: Anchor) {
        x = frame.minX
        y = frame.minY
        width = frame.width
        height = frame.height
        self.anchor = anchor
    }

    public var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    /// The remembered frame at `size`, anchored as remembered, inside
    /// `visible`.
    public func frame(size: CGSize, in visible: CGRect) -> CGRect {
        anchor.resized(frame, to: size, in: visible)
    }
}

/// Remembered frames by panel id and display arrangement, persisted as JSON
/// (`$CANVAS_HOME/frames.json`). A missing or corrupt file reads as empty;
/// writes are atomic. Not thread-safe; the caller serializes access.
public final class FrameStore {
    private struct File: Codable {
        var version = 1
        var arrangements: [String: [String: RememberedFrame]] = [:]
    }

    public let url: URL
    private var file: File

    public init(url: URL) {
        self.url = url
        let data = try? Data(contentsOf: url)
        file = data.flatMap { try? JSONDecoder().decode(File.self, from: $0) } ?? File()
    }

    /// The frame remembered for `id` in this arrangement of `screens`.
    public func remembered(id: String, screens: [ScreenInfo]) -> RememberedFrame? {
        file.arrangements[Desktop.fingerprint(screens)]?[id]
    }

    /// Saves `frame` for `id` under the current arrangement. A frame on no
    /// screen isn't saved.
    public func remember(id: String, frame: CGRect, screens: [ScreenInfo]) {
        guard let screen = Desktop.screen(containing: frame, in: screens) else { return }
        let saved = RememberedFrame(frame: frame, anchor: .nearest(to: frame, in: screen.visibleFrame))
        file.arrangements[Desktop.fingerprint(screens), default: [:]][id] = saved
        save()
    }

    /// Clears `id` in every arrangement.
    public func forget(id: String) {
        let before = file.arrangements
        file.arrangements = before.compactMapValues { frames in
            let kept = frames.filter { $0.key != id }
            return kept.isEmpty ? nil : kept
        }
        if file.arrangements != before { save() }
    }

    /// The protocol's restore rule for a `show` or `toggle`: the remembered
    /// frame when `placement` doesn't position the panel itself. `forget`
    /// clears the id and restores nothing.
    public func restore(id: String, placement: Placement, screens: [ScreenInfo]) -> RememberedFrame? {
        if placement.forget { forget(id: id) }
        return placement.restoresRememberedFrame ? remembered(id: id, screens: screens) : nil
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
