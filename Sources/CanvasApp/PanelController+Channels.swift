import Foundation
import CanvasCore

/// The content's channel hooks, served by the process-wide hub.
extension PanelController {
    func contentDidSubscribe(channel: String, every: Int?) {
        guard isOpen else { return }
        ChannelHub.shared.subscribe(content, channel: channel, every: every)
    }

    func contentDidUnsubscribe(channel: String) {
        ChannelHub.shared.unsubscribe(content, channel: channel)
    }

    func contentDidPublish(channel: String, value: Any, persist: Bool) {
        guard isOpen else { return }
        do {
            try ChannelHub.shared.publish(ChannelMessage(channel: channel, value: value, persist: persist))
        } catch {
            content.consoleError("[canvas] publish: \(error.description)")
        }
    }
}
