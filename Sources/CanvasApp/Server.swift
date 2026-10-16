import AppKit
import CanvasCore

enum WireCommand: String {
    case ping, list, hide, show, toggle, update, eval, trace, move, pub, sub
}

final class Server {
    var panels: [String: PanelController] = [:]
    /// Closed panels waiting hidden for the same request again.
    var resting = RestShelf<PanelController>(capacity: PanelRest.capacity)
    let hosts: HostPools
    let traces = TraceLog()
    /// `eval` runs only in a server started with `CANVAS_TEST=1`.
    let testMode = ProcessInfo.processInfo.environment["CANVAS_TEST"] == "1"
    private var listener: Listener?
    private var observers: [Any] = []

    init(hosts: HostPools) {
        self.hosts = hosts
        hosts.web.openPanels = { [weak self] in self?.openPanels(.web) ?? 0 }
        hosts.native?.openPanels = { [weak self] in self?.openPanels(.native) ?? 0 }
        watchAppearance()
    }

    private func openPanels(_ renderer: Renderer) -> Int {
        panels.values.filter { $0.isOpen && $0.renderer == renderer }.count
    }

    /// Light/dark switches and accent changes in System Settings. Panels see
    /// the new appearance a moment after the app does, hence the extra turn.
    private func watchAppearance() {
        let refresh: () -> Void = { [weak self] in
            DispatchQueue.main.async { self?.panels.values.forEach { $0.refreshAppearance() } }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { _ in refresh() })
        observers.append(NSApplication.shared.observe(\.effectiveAppearance) { _, _ in refresh() })
    }

    func start() throws {
        let listener = try Listener.open()
        self.listener = listener
        for fd in listener.fds {
            let thread = Thread { [weak self] in self?.acceptLoop(fd) }
            thread.name = "canvas.accept"
            thread.qualityOfService = .userInteractive
            thread.start()
        }
        debugLog("listening on \(Paths.socket)")
    }

    func stop() {
        listener?.close()
        listener = nil
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let conn = accept(fd, nil, nil)
            if conn < 0 {
                if errno == EINTR || errno == ECONNABORTED { continue }
                // launchd shares the listening socket's file status and may
                // make it non-blocking again.
                if errno == EAGAIN, Self.waitReadable(fd) { continue }
                return
            }
            let accepted = Clock.now()
            Sock.setBlocking(conn)
            Sock.setNoSigPipe(conn)
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                self?.readRequest(conn, accepted: accepted)
            }
        }
    }

    private static func waitReadable(_ fd: Int32) -> Bool {
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        while true {
            let ready = poll(&pfd, 1, -1)
            if ready > 0 { return pfd.revents & Int16(POLLNVAL) == 0 }
            if ready < 0, errno != EINTR { return false }
        }
    }

    private func readRequest(_ fd: Int32, accepted: UInt64) {
        let reader = LineReader(fd: fd)
        let result = reader.next(deadline: Date().addingTimeInterval(5))
        DispatchQueue.main.async { [weak self] in
            let client = Client(fd: fd, accepted: accepted, reader: reader)
            guard case .line(let line) = result else {
                client.finish()
                return
            }
            self?.dispatch(line, client)
        }
    }

    private func dispatch(_ line: Data, _ client: Client) {
        guard let json = JSON.decode(line) as? [String: Any], let name = json["cmd"] as? String else {
            client.reply(["event": "error", "message": "malformed request"])
            return
        }
        debugLog("request \(name) id=\(json["id"] ?? "-")")
        guard let command = WireCommand(rawValue: name), let handler = Self.handlers[command] else {
            client.reply(["event": "error", "message": "unknown command: \(name)"])
            return
        }
        handler(self, json, client)
    }

    private typealias Handler = (Server, [String: Any], Client) -> Void

    private static let handlers: [WireCommand: Handler] = [
        .ping: { _, _, client in client.reply(["event": "pong"]) },
        .list: { server, _, client in server.list(client) },
        .hide: { server, json, client in server.hide(json, client) },
        .show: { server, json, client in server.show(json, command: .show, client) },
        .toggle: { server, json, client in server.show(json, command: .toggle, client) },
        .update: { server, json, client in server.update(json, client) },
        .eval: { server, json, client in server.evaluate(json, client) },
        .move: { server, json, client in server.move(json, client) },
        .pub: { server, json, client in server.publish(json, client) },
        .sub: { server, json, client in server.subscribe(json, client) },
        .trace: { server, _, client in client.reply(["event": "trace", "stages": server.traces.json]) }
    ]

    private func list(_ client: Client) {
        for panel in panels.values.sorted(by: { $0.created < $1.created }) where panel.isOpen {
            client.send(panel.listing)
        }
        client.finish()
    }

    func startTrace(id: String, command: WireCommand, client: Client, requested: Bool = false) -> TraceRecord {
        let record = TraceRecord(id: id, command: command.rawValue, requested: requested)
        record.mark(.accept, at: client.accepted)
        record.mark(.parsed)
        traces.append(record)
        return record
    }

    /// Forgets the panel, then rests it or recycles its hosts on a later
    /// turn so the close itself stays cheap.
    func panelClosed(_ closed: PanelController) {
        guard panels[closed.id] === closed else { return }
        panels[closed.id] = nil
        if closed.mayRest {
            retire(resting.put(closed.id, closed))
        } else {
            retire([closed])
        }
        hosts.panelsChanged()
    }

    func retire(_ controllers: [PanelController]) {
        let hosts = controllers.flatMap { [$0.host, $0.standby].compactMap { $0 } }
        controllers.forEach { $0.standby = nil }
        guard !hosts.isEmpty else { return }
        DispatchQueue.main.async { [self] in
            hosts.forEach(self.hosts.recycle)
        }
    }

    /// Memory pressure: resting panels go.
    func dropResting() {
        retire(resting.removeAll())
    }
}
