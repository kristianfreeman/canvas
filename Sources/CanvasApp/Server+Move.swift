import Foundation
import CanvasCore

extension Server {
    /// Merges placement fields onto an open panel and answers with its new
    /// frame.
    func move(_ json: [String: Any], _ client: Client) {
        let id = ShowRequest.id(in: json)
        guard let panel = panels[id], panel.isOpen else {
            client.reply(["event": "error", "message": "no canvas with id \(id)"])
            return
        }
        let placement: Placement
        do {
            placement = try Placement(json: json)
        } catch {
            client.reply(["event": "error", "message": error.message])
            return
        }
        let record = startTrace(id: id, command: .move, client: client)
        panel.applyPlacement(placement)
        record.mark(.reply)
        client.reply(["event": "moved", "frame": panel.panel.frame.wire])
    }
}
