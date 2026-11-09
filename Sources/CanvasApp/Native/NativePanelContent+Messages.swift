import Foundation

/// What the runtime posts besides ops, and what the kit's controls send,
/// passed on to the panel as its page's messages would be.
extension NativePanelContent: NativeContextDelegate, NativeEvents {
    func nativeContext(_ context: NativeContext, didPost message: NativeMessage) {
        guard context === self.context, !fellBack, !forwardChannel(message) else { return }
        if case .task(let line, let checked) = message {
            delegate?.contentDidToggleTask(line: line, checked: checked)
        } else {
            forward(message)
        }
    }

    private func forwardChannel(_ message: NativeMessage) -> Bool {
        switch message {
        case .subscribe(let channel, let every):
            delegate?.contentDidSubscribe(channel: channel, every: every)
        case .unsubscribe(let channel):
            delegate?.contentDidUnsubscribe(channel: channel)
        case .publish(let channel, let value, let persist):
            delegate?.contentDidPublish(channel: channel, value: value, persist: persist)
        default:
            return false
        }
        return true
    }

    private func forward(_ message: NativeMessage) {
        switch message {
        case .result(let value): delegate?.contentDidSubmit(value)
        case .close(let reason): close(escape: reason == "escape")
        case .error(let text, _, let needsWeb): reportError(text, needsWeb: needsWeb)
        case .open(let url): open(url)
        case .timedOut(let text): retire(text)
        default: break
        }
    }

    private func close(escape: Bool) {
        if escape {
            delegate?.contentDidRequestEscapeClose()
        } else {
            delegate?.contentDidRequestClose()
        }
    }

    private func reportError(_ text: String, needsWeb: Bool) {
        if needsWeb {
            signalNeedsWeb()
        } else {
            delegate?.contentDidReportError(text)
        }
    }

    // MARK: NativeEvents

    func invoke(_ fn: Int, _ args: [Any]) {
        call(fn, arguments: args)
    }

    func submit(_ value: Any) {
        delegate?.contentDidSubmit(value)
    }

    func close() {
        delegate?.contentDidRequestClose()
    }

    func open(_ url: URL) {
        WebPage.openExternally(url)
    }
}
