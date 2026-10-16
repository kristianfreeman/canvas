import Foundation

public enum SocketError: Error, CustomStringConvertible {
    case pathTooLong(String)
    case syscall(String, Int32)

    public var description: String {
        switch self {
        case .pathTooLong(let path): return "socket path too long: \(path)"
        case .syscall(let name, let code): return "\(name): \(String(cString: strerror(code)))"
        }
    }
}

public enum Sock {
    public static func ignoreSigPipe() {
        signal(SIGPIPE, SIG_IGN)
    }

    static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }

    public static func setNoSigPipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Connections accepted on launchd's socket arrive non-blocking, and
    /// `writeAll` relies on blocking writes.
    public static func setBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0, flags & O_NONBLOCK != 0 { _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) }
    }

    /// Binds and listens at `path`, replacing any stale socket file.
    public static func listen(at path: String) throws -> Int32 {
        guard var addr = address(path) else { throw SocketError.pathTooLong(path) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.syscall("socket", errno) }
        unlink(path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw SocketError.syscall("bind", code)
        }
        chmod(path, 0o600)
        guard Darwin.listen(fd, 16) == 0 else {
            let code = errno
            close(fd)
            throw SocketError.syscall("listen", code)
        }
        return fd
    }

    /// Connects to the socket at `path`. Returns nil if nothing is listening.
    public static func connect(to path: String) -> Int32? {
        guard var addr = address(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            close(fd)
            return nil
        }
        setNoSigPipe(fd)
        return fd
    }

    @discardableResult
    public static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard var cursor = raw.baseAddress else { return true }
            var left = raw.count
            while left > 0 {
                let written = write(fd, cursor, left)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                left -= written
                cursor += written
            }
            return true
        }
    }

    @discardableResult
    public static func writeLine(_ fd: Int32, _ object: Any) -> Bool {
        guard var data = JSON.encode(object) else { return false }
        data.append(0x0A)
        return writeAll(fd, data)
    }
}

/// Reads newline-delimited lines from a file descriptor.
public final class LineReader {
    public enum Result {
        case line(Data)
        case eof
        case timeout
        case error(Int32)
    }

    private static let chunkSize = 64 * 1024

    public let fd: Int32
    private var buffer: [UInt8] = []
    private var chunk = [UInt8](repeating: 0, count: chunkSize)

    public init(fd: Int32) { self.fd = fd }

    /// Returns the next line (without the newline). A nil deadline blocks
    /// forever. At EOF, unterminated bytes come back as a final line.
    public func next(deadline: Date? = nil) -> Result {
        while true {
            if let line = takeLine() { return .line(line) }
            if let deadline, let stop = waitForInput(until: deadline) { return stop }
            if let stop = readChunk() { return stop }
        }
    }

    /// One read of whatever is available (call it when the descriptor is
    /// readable), then every complete line now buffered. `ended` is true at
    /// EOF or on a read error, and then the unterminated tail comes back as a
    /// last line.
    public func drain() -> (lines: [Data], ended: Bool) {
        var lines: [Data] = []
        while let line = takeLine() { lines.append(line) }
        let stop = readChunk()
        while let line = takeLine() { lines.append(line) }
        switch stop {
        case nil, .timeout?:
            return (lines, false)
        case .line(let rest)?:
            lines.append(rest)
            return (lines, true)
        case .eof?, .error?:
            return (lines, true)
        }
    }

    private func takeLine() -> Data? {
        guard let newline = buffer.firstIndex(of: 0x0A) else { return nil }
        let line = Data(buffer[0..<newline])
        buffer.removeSubrange(0...newline)
        return line
    }

    /// Nil once the descriptor is readable.
    private func waitForInput(until deadline: Date) -> Result? {
        while true {
            let ms = deadline.timeIntervalSinceNow * 1000
            guard ms > 0 else { return .timeout }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let rc = poll(&pfd, 1, Int32(min(ms.rounded(.up), Double(Int32.max))))
            if rc > 0 { return nil }
            if rc == 0 { return .timeout }
            if errno != EINTR { return .error(errno) }
        }
    }

    /// Nil when the caller should look for a line again.
    private func readChunk() -> Result? {
        let count = read(fd, &chunk, Self.chunkSize)
        if count > 0 {
            buffer.append(contentsOf: chunk[0..<count])
            return nil
        }
        if count == 0 { return remainder() }
        if errno == EINTR { return nil }
        return errno == EAGAIN || errno == EWOULDBLOCK ? .timeout : .error(errno)
    }

    private func remainder() -> Result {
        guard !buffer.isEmpty else { return .eof }
        let rest = Data(buffer)
        buffer.removeAll()
        return .line(rest)
    }
}
