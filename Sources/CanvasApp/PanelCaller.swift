import Foundation
import CanvasCore

/// The CLI caller waiting on a panel, if any, and whether it still expects
/// to hear how the first render went.
final class PanelCaller {
    let panelID: String
    private var client: Client?
    private var awaitingRender = false
    /// The latest caller's trace, kept after the call ends so later stages
    /// still land in the server's trace log.
    private(set) var trace: TraceRecord?

    init(panelID: String) { self.panelID = panelID }

    var isAttached: Bool { client != nil }

    /// A stream sets its own `onEnd` before this, and keeps it.
    func attach(_ client: Client) {
        self.client = client
        trace = client.trace
        awaitingRender = true
        if client.onEnd == nil {
            client.onEnd = { [weak self, weak client] in
                guard let self, let client, self.client === client else { return }
                debugLog("caller for \(self.panelID) disconnected")
                self.client = nil
                client.finish()
            }
        }
        client.startReading()
    }

    /// Ends the call with a final event.
    func finish(_ event: [String: Any]) {
        guard let client else { return }
        self.client = nil
        client.reply(event)
    }

    /// Errors end the call. A render ends it unless the caller waits for a
    /// result or streams data, in which case the connection stays open.
    func renderFinished(error: String?, wait: Bool, stream: Bool) {
        guard awaitingRender, let client else { return }
        awaitingRender = false
        if let error {
            finish(traced(["event": "error", "message": error]))
            return
        }
        let event = traced(["event": "rendered"])
        if wait {
            client.send(event)
        } else if stream {
            client.send(event)
            self.client = nil
        } else {
            finish(event)
        }
    }

    private func traced(_ event: [String: Any]) -> [String: Any] {
        guard let trace else { return event }
        trace.mark(.reply)
        guard trace.requested else { return event }
        var event = event
        event["trace"] = trace.stages
        return event
    }
}
