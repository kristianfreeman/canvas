import Foundation
import CanvasCore

/// `{"data":V}` lines on a connection, from `update --stream` or
/// `show --stream`, feeding a panel's data.
final class DataStream {
    private let client: Client
    private weak var panel: PanelController?
    /// Whether EOF ends the call with `updated`. A `--wait` show keeps
    /// waiting for its result instead.
    private let answersAtEnd: Bool

    init(client: Client, panel: PanelController, answersAtEnd: Bool) {
        self.client = client
        self.panel = panel
        self.answersAtEnd = answersAtEnd
    }

    func start() {
        client.onLine = { [weak self] line in self?.received(line) }
        client.onEnd = { [weak self] in self?.ended() }
        panel?.add(stream: self)
        client.startReading()
    }

    func panelClosed() {
        client.reply(["event": "closed"])
    }

    private func received(_ line: Data) {
        guard let object = JSON.decode(line) as? [String: Any], let value = object["data"] else {
            debugLog("stream line without data: \(String(bytes: line.prefix(200), encoding: .utf8) ?? "<binary>")")
            return
        }
        panel?.offer(data: value)
    }

    private func ended() {
        panel?.remove(stream: self)
        if answersAtEnd { client.reply(["event": "updated"]) }
    }
}
