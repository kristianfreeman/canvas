import Foundation
import CanvasCore

/// Calls `onChange` with the new text (nil when the file is gone) whenever
/// config.toml's contents change: edited in place, replaced by an editor's
/// atomic save, created, or deleted. It watches the file when it exists and
/// the nearest existing folder above it, so it also sees the file, or its
/// folder, appear later.
final class ConfigWatcher {
    let url: URL
    private let onChange: (String?) -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var debounce: DispatchWorkItem?
    private var last: String?
    private var stopped = false

    init(url: URL, onChange: @escaping (String?) -> Void) {
        self.url = url
        self.onChange = onChange
        last = read()
        arm()
    }

    deinit { stop() }

    func stop() {
        stopped = true
        debounce?.cancel()
        sources.forEach { $0.cancel() }
        sources = []
    }

    private func read() -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    /// Watches the file, if it is there, and the nearest existing folder.
    private func arm() {
        sources.forEach { $0.cancel() }
        let folder = ConfigWatch.nearestFolder(of: url) { FileManager.default.fileExists(atPath: $0) }
        sources = [url.path, folder.path].compactMap(watch)
    }

    private func watch(_ path: String) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: .main)
        source.setEventHandler { [weak self] in self?.changed() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    /// Debounced: an editor's save can come as several events. Re-arms,
    /// since a replaced file or a new folder needs a new watch.
    private func changed() {
        debounce?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.arm()
            let text = self.read()
            guard text != self.last else { return }
            self.last = text
            self.onChange(text)
        }
        debounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }
}
