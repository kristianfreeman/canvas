import AppKit
import CanvasCore

/// Data updates (one-shot and streamed) and the test hook.
extension PanelController {
    /// One-shot `update`: new data props now; `completion` runs once the
    /// content has applied them.
    func update(data: Any, completion: @escaping () -> Void) {
        request.data = data
        content.setData(data) { [weak self] height in
            self?.dataApplied(height: height)
            completion()
        }
    }

    /// A streamed value: coalesced to at most one `setData` per display
    /// frame, newest wins.
    func offer(data: Any) {
        guard isOpen else { return }
        request.data = data
        guard let delay = coalescer.offer(data, now: Clock.now()) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(delay))) { [weak self] in
            self?.flushData()
        }
    }

    private func flushData() {
        guard isOpen, let data = coalescer.flush(now: Clock.now()) else { return }
        content.setData(data) { [weak self] height in self?.dataApplied(height: height) }
    }

    private func dataApplied(height: CGFloat?) {
        guard isOpen, let height, height > 0 else { return }
        layout.contentHeight = height
        applyFrame()
    }

    func add(stream: DataStream) {
        streams.append(stream)
    }

    func remove(stream: DataStream) {
        streams.removeAll { $0 === stream }
    }

    /// Runs `js` as a function body in the content (`eval`, tests only).
    func evaluate(_ js: String, completion: @escaping (Result<Any, Error>) -> Void) {
        content.evaluate(js, completion: completion)
    }
}
