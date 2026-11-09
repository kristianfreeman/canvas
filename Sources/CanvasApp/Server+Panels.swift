import AppKit
import CanvasCore

/// The commands that act on panels.
extension Server {
    func hide(_ json: [String: Any], _ client: Client) {
        let all = json["all"] as? Bool == true
        let record = startTrace(id: all ? "*" : ShowRequest.id(in: json), command: .hide, client: client)
        if all {
            for panel in Array(panels.values) { panel.close() }
        } else {
            panels[ShowRequest.id(in: json)]?.close()
        }
        record.mark(.reply)
        client.reply(["event": "hidden"])
    }

    func show(_ json: [String: Any], command: WireCommand, _ client: Client) {
        let request: ShowRequest
        do {
            request = try ShowRequest(json)
        } catch {
            client.reply(["event": "error", "message": error.message])
            return
        }
        if let message = applyHotkey(request.hotkey, json: json, id: request.id) {
            client.reply(["event": "error", "message": message])
            return
        }
        let record = startTrace(id: request.id, command: command, client: client, requested: request.trace)
        client.trace = record
        if command == .toggle, let existing = panels[request.id], existing.isOpen, !existing.stashed {
            record.note = "hide"
            existing.close()
            record.mark(.reply)
            client.reply(["event": "hidden"])
            return
        }
        if let existing = panels[request.id] {
            record.note = "replace"
            existing.replace(with: request, caller: client)
            return
        }
        if !reopenResting(request, record: record, client) {
            open(request, record: record, client)
        }
    }

    /// Shows the id's resting panel if it draws the same thing; a different
    /// one is retired.
    private func reopenResting(_ request: ShowRequest, record: TraceRecord, _ client: Client) -> Bool {
        guard let rested = resting.take(request.id) else { return false }
        guard PanelRest.sameShow(rested.request, request) else {
            retire([rested])
            return false
        }
        record.note = "rest"
        panels[request.id] = rested
        hosts.panelsChanged()
        rested.reopen(request, caller: client)
        return true
    }

    private func open(_ request: ShowRequest, record: TraceRecord, _ client: Client) {
        let renderer = hosts.route(for: request)
        guard renderer == .native || hosts.hasWebRenderer else {
            client.reply(["event": "error", "message": "web renderer not found at \(hosts.indexURL.path)"])
            return
        }
        let (host, pooled) = hosts.take(renderer)
        record.note = pooled ? "new" : "fresh"
        let controller = PanelController(request: request, host: host)
        controller.hosts = hosts
        controller.onClose = { [weak self] closed in
            self?.panelClosed(closed)
            if let stack = closed.stack { self?.restack(stack) }
        }
        controller.onReveal = { [weak self] in self?.hosts.refillWhenIdle() }
        controller.onRestack = { [weak self] group in self?.restack(group) }
        controller.onRendererChange = { [weak self] in self?.hosts.panelsChanged() }
        panels[request.id] = controller
        hosts.panelsChanged()
        controller.attach(caller: client)
        controller.start()
    }

    /// Lays out a stack group's open panels, oldest first, on the oldest
    /// one's screen and with its anchor.
    func restack(_ group: String) {
        let members = panels.values.filter { $0.isOpen && !$0.stashed && $0.stack == group }
            .sorted { $0.created < $1.created }
        guard let first = members.first, let screen = first.layout.screen else { return }
        let frames = PanelLayout.stackedFrames(members.map(\.layout), on: screen, mouse: first.desktop.mouse)
        for (member, frame) in zip(members, frames) {
            member.setFrame(frame)
        }
    }

    func update(_ json: [String: Any], _ client: Client) {
        let id = ShowRequest.id(in: json)
        guard let panel = panels[id], panel.isOpen else {
            client.reply(["event": "error", "message": "no canvas with id \(id)"])
            return
        }
        if json["stream"] as? Bool == true {
            DataStream(client: client, panel: panel, answersAtEnd: true).start()
            if let data = json["data"] { panel.offer(data: data) }
            return
        }
        guard let data = json["data"] else {
            client.reply(["event": "error", "message": "update needs data"])
            return
        }
        panel.update(data: data) { client.reply(["event": "updated"]) }
    }

    func evaluate(_ json: [String: Any], _ client: Client) {
        guard testMode else {
            client.reply(["event": "error", "message": "eval needs a server started with CANVAS_TEST=1"])
            return
        }
        let id = ShowRequest.id(in: json)
        guard let panel = panels[id], panel.isOpen, let js = json["js"] as? String else {
            client.reply(["event": "error", "message": "eval needs js and an open canvas id"])
            return
        }
        panel.evaluate(js) { result in
            switch result {
            case .success(let value):
                let safe = JSON.encode(value) == nil ? String(describing: value) : value
                client.reply(["event": "value", "value": safe])
            case .failure(let error):
                client.reply(["event": "error", "message": WebPage.message(error)])
            }
        }
    }
}
