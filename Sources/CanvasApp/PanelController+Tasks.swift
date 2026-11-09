import Foundation
import CanvasCore

/// Clicking a task checkbox in a Markdown panel checks or unchecks that
/// item in the source, and in the file when the panel shows one.
extension PanelController {
    func contentDidToggleTask(line: Int, checked: Bool) {
        guard isOpen, request.kind == "markdown" else { return }
        if let path = request.path {
            toggle(line: line, checked: checked, inFile: path)
        } else if let next = TaskList.setChecked(checked, line: line, in: request.source) {
            show(source: next)
        }
    }

    private func toggle(line: Int, checked: Bool, inFile path: String) {
        guard let disk = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        // The file changed since it was drawn: line numbers may have moved,
        // so the click is dropped and the new text drawn instead.
        guard disk == request.source else { return fileChanged() }
        guard let next = TaskList.setChecked(checked, line: line, in: disk), next != disk else { return }
        do {
            try next.write(toFile: path, atomically: false, encoding: .utf8)
        } catch {
            content.consoleError("[canvas] could not save \(path): \(error.localizedDescription)")
            return
        }
        debugLog("task \(id) line \(line) checked=\(checked)")
        show(source: next)
    }

    private func show(source: String) {
        guard source != request.source else { return }
        request.source = source
        render()
    }
}
