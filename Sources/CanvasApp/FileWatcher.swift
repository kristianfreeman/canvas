import Foundation
import CanvasCore

/// Calls `onChange` (debounced, on the main queue) when the file at `path`
/// changes, including editors that save by replacing the file.
final class FileWatcher {
    let path: String
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private var stopped = false

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
        open(attempt: 0, notify: false)
    }

    deinit { stop() }

    func stop() {
        stopped = true
        debounce?.cancel()
        debounce = nil
        source?.cancel()
        source = nil
    }

    private func open(attempt: Int, notify: Bool) {
        guard !stopped else { return }
        let fd = Darwin.open(path, O_EVTONLY)
        guard fd >= 0 else {
            retry(after: attempt, notify: notify)
            return
        }
        watch(fd)
        if notify { fire() }
    }

    /// The file can be briefly missing while an editor replaces it.
    private func retry(after attempt: Int, notify: Bool) {
        guard attempt < 20 else {
            debugLog("gave up watching \(path)")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.open(attempt: attempt + 1, notify: notify)
        }
    }

    private func watch(_ fd: Int32) {
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            self.handle(src.data, from: src)
        }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    private func handle(_ events: DispatchSource.FileSystemEvent, from src: DispatchSourceFileSystemObject) {
        guard events.contains(.delete) || events.contains(.rename) else {
            fire()
            return
        }
        src.cancel()
        if source === src { source = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.open(attempt: 0, notify: true)
        }
    }

    private func fire() {
        guard !stopped else { return }
        debounce?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.onChange()
        }
        debounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }
}
