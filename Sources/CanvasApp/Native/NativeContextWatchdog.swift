import Foundation

/// Reports a call that runs past the time limit when JavaScriptCore can't
/// stop it (no `JSContextGroupSetExecutionTimeLimit`). The call keeps running.
final class NativeContextWatchdog {
    private let limit: TimeInterval
    private let onHang: () -> Void
    private let lock = NSLock()
    private var call = 0
    private var running = false

    init(limit: TimeInterval, onHang: @escaping () -> Void) {
        self.limit = limit
        self.onHang = onHang
    }

    func begin() {
        lock.lock()
        call += 1
        running = true
        let current = call
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + limit) { [weak self] in
            self?.check(current)
        }
    }

    func end() {
        lock.lock()
        running = false
        lock.unlock()
    }

    private func check(_ expected: Int) {
        lock.lock()
        let hung = running && call == expected
        lock.unlock()
        if hung { onHang() }
    }
}
