import Foundation
import CanvasCore

extension Server {
    var channelHub: ChannelHub { .shared }

    func publish(_ json: [String: Any], _ client: Client) {
        let request: PubRequest
        do {
            request = try PubRequest(json)
        } catch {
            client.reply(["event": "error", "message": error.description])
            return
        }
        if request.stream {
            publishStream(request, client)
            return
        }
        do {
            try channelHub.publish(request.message(request.value ?? NSNull()))
            client.reply(["event": "ok"])
        } catch {
            client.reply(["event": "error", "message": error.description])
        }
    }

    /// One value per line until the peer shuts down its write side. Lines
    /// that aren't JSON are skipped.
    private func publishStream(_ request: PubRequest, _ client: Client) {
        var first = true
        client.onLine = { [channelHub] line in
            guard let value = JSON.decode(line) else {
                debugLog("pub \(request.channel): skipping a line that isn't JSON")
                return
            }
            try? channelHub.publish(request.message(value, first: first))
            first = false
        }
        client.onEnd = { [weak client] in client?.reply(["event": "ok"]) }
        client.startReading()
    }

    /// History, then live messages, until either side closes.
    func subscribe(_ json: [String: Any], _ client: Client) {
        let request: SubRequest
        do {
            request = try SubRequest(json)
        } catch {
            client.reply(["event": "error", "message": error.description])
            return
        }
        Self.allowSlowReader(client.fd)
        let token = channelHub.attach(request) { [weak client] event in client?.send(event) }
        let end = { [channelHub, weak client] in
            channelHub.detach(token)
            client?.finish()
        }
        guard !client.finished else {
            end()
            return
        }
        client.onLine = { _ in }
        client.onEnd = end
        client.startReading()
    }

    /// A subscriber that stops reading is dropped once its buffer fills,
    /// rather than blocking the main thread on a write.
    private static func allowSlowReader(_ fd: Int32) {
        var size: Int32 = 1 << 20
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
    }
}
