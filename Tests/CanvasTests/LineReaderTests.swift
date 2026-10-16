import CanvasCore
import Foundation
import Testing

/// A connected pair whose reads give up after `receiveTimeout`, so a broken
/// reader or a missing writer fails the test instead of hanging it.
private func socketPair(receiveTimeout: Int = 5) -> (reader: Int32, writer: Int32) {
    var fds: [Int32] = [-1, -1]
    let rc = socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
    precondition(rc == 0, "socketpair failed: \(errno)")
    var timeout = timeval(tv_sec: receiveTimeout, tv_usec: 0)
    for fd in fds {
        Sock.setNoSigPipe(fd)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
    return (fds[0], fds[1])
}

/// Writes `bytes` from a background thread in chunks of the given sizes
/// (cycled), then closes the descriptor. Stops early if the reader goes
/// away. The returned semaphore signals when the writer is done.
@discardableResult
private func write(_ bytes: [UInt8], to fd: Int32, chunks: [Int], delay: TimeInterval = 0) -> DispatchSemaphore {
    let done = DispatchSemaphore(value: 0)
    let thread = Thread {
        defer {
            close(fd)
            done.signal()
        }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        var offset = 0
        var index = 0
        while offset < bytes.count {
            let size = min(chunks[index % chunks.count], bytes.count - offset)
            guard Sock.writeAll(fd, Data(bytes[offset..<offset + size])) else { return }
            offset += size
            index += 1
        }
    }
    thread.start()
    return done
}

/// Reads to the end, but never more than `limit` lines, so a reader that
/// stops consuming input fails instead of looping.
private func readAll(_ reader: LineReader, limit: Int) -> (lines: [Data], end: String) {
    var lines: [Data] = []
    while lines.count <= limit {
        switch reader.next(deadline: Date().addingTimeInterval(10)) {
        case .line(let line): lines.append(line)
        case .eof: return (lines, "eof")
        case .timeout: return (lines, "timeout")
        case .error(let code): return (lines, "error \(code)")
        }
    }
    return (lines, "over limit")
}

@Suite(.serialized) struct LineReaderFramingTests {
    struct Stream {
        let lines: [Data]
        let bytes: [UInt8]
        let chunks: [Int]
    }

    /// Random NDJSON-ish lines, including empty and oversized ones, cut into
    /// random chunks. Every fourth seed writes one byte at a time.
    static func stream(seed: UInt64) -> Stream {
        var rng = SeededRNG(seed: seed)
        let oneByte = seed.isMultiple(of: 4)
        let lines: [Data] = (0..<Int.random(in: 1...40, using: &rng)).map { _ in
            let big = !oneByte && Int.random(in: 0..<25, using: &rng) == 0
            let length = big ? Int.random(in: 65_000...140_000, using: &rng) : Int.random(in: 0...300, using: &rng)
            return Data((0..<length).map { _ in UInt8.random(in: 0x20...0x7E, using: &rng) })
        }
        var bytes: [UInt8] = lines.flatMap { Array($0) + [0x0A] }
        if !seed.isMultiple(of: 2), let last = lines.last, !last.isEmpty { bytes.removeLast() }
        let maxChunk = oneByte ? 1 : [2, 7, 64, 4096, 100_000].randomElement(using: &rng) ?? 1
        let chunks = (0..<64).map { _ in Int.random(in: 1...maxChunk, using: &rng) }
        return Stream(lines: lines, bytes: bytes, chunks: chunks)
    }

    @Test(arguments: 0..<96)
    func yieldsExactlyTheWrittenLines(seed: UInt64) {
        let stream = Self.stream(seed: seed)
        let (readFD, writeFD) = socketPair()
        let writer = write(stream.bytes, to: writeFD, chunks: stream.chunks)
        let result = readAll(LineReader(fd: readFD), limit: stream.lines.count)
        close(readFD)
        #expect(writer.wait(timeout: .now() + 5) == .success)
        #expect(result.end == "eof")
        #expect(result.lines.count == stream.lines.count)
        #expect(result.lines == stream.lines)
    }

    @Test func unterminatedLastLineComesBackAtEOF() {
        let (readFD, writeFD) = socketPair()
        defer { close(readFD) }
        write(Array("{\"a\":1}\n{\"b\":2}".utf8), to: writeFD, chunks: [3])
        let result = readAll(LineReader(fd: readFD), limit: 2)
        #expect(result.lines == [Data("{\"a\":1}".utf8), Data("{\"b\":2}".utf8)])
        #expect(result.end == "eof")
    }

    @Test func emptyStreamIsEOF() {
        let (readFD, writeFD) = socketPair()
        defer { close(readFD) }
        close(writeFD)
        let result = readAll(LineReader(fd: readFD), limit: 0)
        #expect(result.lines.isEmpty)
        #expect(result.end == "eof")
    }
}

@Suite(.serialized) struct LineReaderDeadlineTests {
    @Test func timesOutWhenNothingArrives() {
        let (readFD, writeFD) = socketPair()
        defer { close(readFD); close(writeFD) }
        let start = Date()
        let result = LineReader(fd: readFD).next(deadline: start.addingTimeInterval(0.05))
        let elapsed = Date().timeIntervalSince(start)
        guard case .timeout = result else {
            Issue.record("expected timeout, got \(result)")
            return
        }
        #expect(elapsed >= 0.045)
        #expect(elapsed < 1)
    }

    @Test func partialLineSurvivesATimeout() {
        let (readFD, writeFD) = socketPair()
        defer { close(readFD); close(writeFD) }
        let reader = LineReader(fd: readFD)
        Sock.writeAll(writeFD, Data("abc".utf8))
        guard case .timeout = reader.next(deadline: Date().addingTimeInterval(0.05)) else {
            Issue.record("expected timeout on a partial line")
            return
        }
        Sock.writeAll(writeFD, Data("def\n".utf8))
        guard case .line(let line) = reader.next(deadline: Date().addingTimeInterval(1)) else {
            Issue.record("expected the completed line")
            return
        }
        #expect(line == Data("abcdef".utf8))
    }

    @Test func bufferedLineIsReturnedEvenPastTheDeadline() {
        let (readFD, writeFD) = socketPair()
        defer { close(readFD); close(writeFD) }
        let reader = LineReader(fd: readFD)
        Sock.writeAll(writeFD, Data("one\ntwo\n".utf8))
        guard case .line(let first) = reader.next(deadline: Date().addingTimeInterval(1)) else {
            Issue.record("expected the first line")
            return
        }
        guard case .line(let second) = reader.next(deadline: Date.distantPast) else {
            Issue.record("expected the buffered second line")
            return
        }
        #expect([first, second] == [Data("one".utf8), Data("two".utf8)])
    }

    @Test func noDeadlineWaitsForData() {
        let (readFD, writeFD) = socketPair()
        defer { close(readFD) }
        let writer = write(Array("late\n".utf8), to: writeFD, chunks: [5], delay: 0.1)
        let start = Date()
        guard case .line(let line) = LineReader(fd: readFD).next() else {
            Issue.record("expected a line")
            return
        }
        #expect(line == Data("late".utf8))
        #expect(Date().timeIntervalSince(start) >= 0.09)
        #expect(writer.wait(timeout: .now() + 5) == .success)
    }
}
