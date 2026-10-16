import CanvasCore
import Foundation

/// The main-thread side of a context for one panel: applies each ops batch
/// to `tree` and passes every other message on to `delegate`.
final class NativeContextTree: NativeContextDelegate {
    private(set) var tree = ViewTree()
    weak var delegate: NativeContextDelegate?
    /// Called after each batch is applied, for layout.
    var didApply: (() -> Void)?
    /// The last batch that failed to apply. The tree keeps the ops before
    /// the failing one.
    private(set) var lastError: Error?

    func nativeContext(_ context: NativeContext, didPost message: NativeMessage) {
        guard case .ops(let ops) = message else {
            delegate?.nativeContext(context, didPost: message)
            return
        }
        do {
            try tree.apply(ops)
        } catch {
            lastError = error
            debugLog("native ops failed: \(error)")
        }
        didApply?()
    }

    /// A new, empty tree, for a context that was reset.
    func reset() {
        tree = ViewTree()
        lastError = nil
    }
}
