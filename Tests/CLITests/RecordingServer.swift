import CanvasCore
import Foundation
import TestSupport

/// A stand-in for canvas-server on `<home>/canvas.sock`. Each connection
/// gets the next script in order; it records the request line and any
/// streamed lines, then plays its steps. Connections past the script are
/// recorded and closed.
final class RecordingServer {
    enum Step: Sendable {
        /// One raw line, newline added.
        case send(String)
        /// Records the client's lines until it shuts down its write side.
        case readToEnd
        /// Holds the connection open until the client goes away.
        case hold
    }

    struct Connection {
        var request: String
        var streamed: [String] = []

        var json: [String: Any] {
            JSON.decode(Data(request.utf8)) as? [String: Any] ?? [:]
        }
    }

    let home = TempDir()
    private let scripts: [[Step]]
    private let listener: Int32
    private let lock = NSLock()
    private var recorded: [Int: Connection] = [:]
    private var stopped = false
    private let handlers = DispatchGroup()

    init(_ scripts: [[Step]]) throws {
        self.scripts = scripts
        listener = try Sock.listen(at: home.url.appendingPathComponent("canvas.sock").path)
        Thread { [weak self] in self?.acceptLoop() }.start()
    }

    /// Polls so `stop` ends the loop; a close alone doesn't wake `accept`.
    private func acceptLoop() {
        var index = 0
        while !isStopped {
            var pfd = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            guard poll(&pfd, 1, 20) > 0 else { continue }
            let fd = accept(listener, nil, nil)
            guard fd >= 0 else { continue }
            handle(fd, index: index)
            index += 1
        }
        close(listener)
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    /// The environment that points the CLI here and keeps it from starting
    /// a real server.
    var environment: [String: String] {
        ["CANVAS_HOME": home.path, "CANVAS_NO_AUTOSTART": "1"]
    }

    /// The recorded connections in accept order, once every handler is done.
    func connections() -> [Connection] {
        _ = handlers.wait(timeout: .now() + 5)
        lock.lock()
        defer { lock.unlock() }
        return recorded.keys.sorted().compactMap { recorded[$0] }
    }

    private func handle(_ fd: Int32, index: Int) {
        Sock.setNoSigPipe(fd)
        let steps = index < scripts.count ? scripts[index] : []
        handlers.enter()
        DispatchQueue.global().async { [self] in
            defer {
                close(fd)
                handlers.leave()
            }
            let reader = LineReader(fd: fd)
            guard case .line(let line) = reader.next(deadline: Date().addingTimeInterval(5)) else { return }
            record(index) { $0 = Connection(request: line.text) }
            for step in steps { play(step, reader: reader, index: index) }
        }
    }

    private func play(_ step: Step, reader: LineReader, index: Int) {
        switch step {
        case .send(let line):
            Sock.writeAll(reader.fd, Data((line + "\n").utf8))
        case .readToEnd, .hold:
            while case .line(let line) = reader.next(deadline: Date().addingTimeInterval(10)) {
                if case .readToEnd = step {
                    record(index) { $0?.streamed.append(line.text) }
                }
            }
        }
    }

    private func record(_ index: Int, _ change: (inout Connection?) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        change(&recorded[index])
    }
}
