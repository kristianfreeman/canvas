import Foundation
import CanvasCore

/// One CLI connection. Writes happen on the main thread. Once reading
/// starts, a background queue reads whatever the peer sends after the
/// request and hands complete lines to the main thread.
final class Client {
    let fd: Int32
    let accepted: UInt64
    var trace: TraceRecord?
    private(set) var finished = false
    /// A line the peer sent after the request.
    var onLine: ((Data) -> Void)?
    /// The peer shut down its write side or went away.
    var onEnd: (() -> Void)?

    private let reader: LineReader
    private var readSource: DispatchSourceRead?
    private var reading = false

    private static let readQueue = DispatchQueue(label: "canvas.client-read", qos: .userInitiated)

    init(fd: Int32, accepted: UInt64, reader: LineReader) {
        self.fd = fd
        self.accepted = accepted
        self.reader = reader
    }

    /// Starts delivering `onLine` and `onEnd`. Calling it again does nothing.
    func startReading() {
        guard readSource == nil, !finished else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: Self.readQueue)
        let reader = reader
        source.setEventHandler { [weak self, weak source] in
            let (lines, ended) = reader.drain()
            if ended { source?.cancel() }
            DispatchQueue.main.async { self?.received(lines, ended: ended) }
        }
        // Strong on purpose: the descriptor must still be closed if the
        // last other reference goes away while the cancel is pending.
        source.setCancelHandler { [self] in
            DispatchQueue.main.async { self.readerStopped() }
        }
        readSource = source
        reading = true
        source.resume()
    }

    @discardableResult
    func send(_ object: [String: Any]) -> Bool {
        guard !finished else { return false }
        guard Sock.writeLine(fd, object) else {
            let callback = onEnd
            finish()
            callback?()
            return false
        }
        return true
    }

    /// Sends a final event and closes the connection.
    func reply(_ object: [String: Any]) {
        send(object)
        finish()
    }

    func finish() {
        guard !finished else { return }
        finished = true
        onLine = nil
        onEnd = nil
        if reading {
            readSource?.cancel()
        } else {
            close(fd)
        }
    }

    private func received(_ lines: [Data], ended: Bool) {
        for line in lines where !finished {
            onLine?(line)
        }
        if ended, !finished { onEnd?() }
    }

    /// The descriptor closes once nothing reads it and the call is over.
    private func readerStopped() {
        guard reading else { return }
        reading = false
        readSource = nil
        if finished { close(fd) }
    }
}
