import Foundation
import os

/// A thread with its own run loop, for one JavaScript context. Work and
/// timers run on that run loop; nothing else touches the context.
final class JSThread: Thread {
    private var runLoop: CFRunLoop?
    private let started = DispatchSemaphore(value: 0)
    private var timers: [Int: CFRunLoopTimer] = [:] {
        didSet { pending.withLock { $0 = !timers.isEmpty } }
    }
    private let pending = OSAllocatedUnfairLock(initialState: false)
    /// Whether a timer is scheduled. Any thread.
    var hasTimers: Bool { pending.withLock { $0 } }
    /// Runs on this thread when a timer from `schedule` fires. Set it
    /// before scheduling.
    var onTimer: (Int) -> Void = { _ in }

    init(name: String) {
        super.init()
        self.name = name
        stackSize = 8 << 20
        qualityOfService = .userInitiated
        start()
        started.wait()
    }

    override func main() {
        let loop = CFRunLoopGetCurrent()
        var context = CFRunLoopSourceContext()
        let keepAlive = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)
        CFRunLoopAddSource(loop, keepAlive, .defaultMode)
        runLoop = loop
        started.signal()
        while !isCancelled {
            autoreleasepool {
                _ = CFRunLoopRunInMode(.defaultMode, 60, false)
            }
        }
        CFRunLoopRemoveSource(loop, keepAlive, .defaultMode)
    }

    /// Runs `block` on this thread, after the work queued before it.
    func perform(_ block: @escaping () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    /// Calls `onTimer(id)` after `delay` seconds, and every `delay` after
    /// that when `repeats`. Call on this thread.
    func schedule(_ id: Int, after delay: TimeInterval, repeats: Bool) {
        cancelTimer(id)
        let interval = repeats ? max(delay, 0.001) : 0
        let timer = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + max(delay, 0), interval, 0, 0
        ) { [weak self] _ in
            if !repeats { self?.timers[id] = nil }
            self?.onTimer(id)
        }
        timers[id] = timer
        CFRunLoopAddTimer(runLoop, timer, .defaultMode)
    }

    /// Call on this thread.
    func cancelTimer(_ id: Int) {
        guard let timer = timers.removeValue(forKey: id) else { return }
        CFRunLoopTimerInvalidate(timer)
    }

    /// Call on this thread.
    func cancelAllTimers() {
        timers.values.forEach(CFRunLoopTimerInvalidate)
        timers.removeAll()
    }

    /// Ends the run loop once the queued work has run.
    func stop() {
        perform { [self] in
            cancelAllTimers()
            cancel()
            if let runLoop { CFRunLoopStop(runLoop) }
        }
    }
}
