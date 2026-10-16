import Foundation
import CanvasCore

/// The listening sockets: launchd's when it started the server for socket
/// activation (socket name `canvas`), otherwise one bound here.
struct Listener {
    let fds: [Int32]
    /// launchd owns the socket file, so it must never be unlinked here.
    let ownedByLaunchd: Bool

    static func open() throws -> Self {
        if let fds = activatedSockets() {
            debugLog("using \(fds.count) socket(s) from launchd")
            return Self(fds: fds, ownedByLaunchd: true)
        }
        return Self(fds: [try Sock.listen(at: Paths.socket)], ownedByLaunchd: false)
    }

    func close() {
        for fd in fds { Darwin.close(fd) }
        if !ownedByLaunchd { unlink(Paths.socket) }
    }

    /// Nil when launchd didn't start us (it answers ESRCH) or has no socket
    /// by that name.
    private static func activatedSockets() -> [Int32]? {
        let out = UnsafeMutablePointer<UnsafeMutablePointer<Int32>>.allocate(capacity: 1)
        defer { out.deallocate() }
        var count = 0
        guard launch_activate_socket("canvas", out, &count) == 0 else { return nil }
        let list = out.pointee
        defer { free(list) }
        guard count > 0 else { return nil }
        let fds = (0..<count).map { list[$0] }
        fds.forEach(Sock.setBlocking)
        return fds
    }
}
