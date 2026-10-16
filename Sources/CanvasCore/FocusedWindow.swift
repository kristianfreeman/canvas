import CoreGraphics
import Foundation

/// The frontmost app's focused window, read from `CGWindowListCopyWindowInfo`
/// entries. Window bounds need no Screen Recording or Accessibility
/// permission; only titles would.
public enum FocusedWindow {
    /// The first ordinary window (layer 0, visible, with an area) that `pid`
    /// owns, in AppKit global coordinates. `windows` are listed front to
    /// back, so the first match is the app's frontmost window.
    /// `mainScreenHeight` is the height of the screen with the menu bar,
    /// whose top-left corner is the window list's origin.
    public static func frame(of pid: Int32, in windows: [[String: Any]], mainScreenHeight: CGFloat) -> CGRect? {
        windows.lazy
            .filter { owner($0) == pid && isOrdinary($0) }
            .compactMap(bounds)
            .first { $0.width > 0 && $0.height > 0 }
            .map { appKitRect(fromWindowList: $0, mainScreenHeight: mainScreenHeight) }
    }

    /// Window-list coordinates (origin top-left of the main screen, y down)
    /// to AppKit's (origin bottom-left, y up).
    public static func appKitRect(fromWindowList rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func owner(_ window: [String: Any]) -> Int32? {
        (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
    }

    private static func isOrdinary(_ window: [String: Any]) -> Bool {
        let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        return layer == 0 && alpha > 0
    }

    private static func bounds(_ window: [String: Any]) -> CGRect? {
        guard let dictionary = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }
}
