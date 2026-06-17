import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Reads the active tab's URL + title from supported browsers via Apple Events.
/// This needs macOS Automation permission (granted per-browser, with a visible prompt) —
/// it reads page metadata only, never page content or keystrokes.
public struct BrowserInspector {
    public init() {}

    /// AppleScript snippets keyed by browser bundle ID. Chromium browsers share a dialect.
    private static let scripts: [String: String] = {
        let chromium = { (app: String) in
            "tell application \"\(app)\" to return (URL of active tab of front window) & \"\\n\" & (title of active tab of front window)"
        }
        return [
            "com.apple.Safari": "tell application \"Safari\" to return (URL of current tab of front window) & \"\\n\" & (name of current tab of front window)",
            "com.google.Chrome": chromium("Google Chrome"),
            "com.microsoft.edgemac": chromium("Microsoft Edge"),
            "com.brave.Browser": chromium("Brave Browser"),
            "company.thebrowser.Browser": chromium("Arc"),
        ]
    }()

    public static func isSupportedBrowser(bundleID: String) -> Bool {
        scripts[bundleID] != nil
    }

    /// Returns (url, title) for the front tab, or nil if unsupported / permission denied / no window.
    public func activeTab(bundleID: String) -> (url: String, title: String)? {
        #if canImport(AppKit)
        guard let source = BrowserInspector.scripts[bundleID],
              let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, let combined = result.stringValue else { return nil }
        let parts = combined.components(separatedBy: "\n")
        let url = parts.first ?? ""
        let title = parts.count > 1 ? parts[1...].joined(separator: "\n") : ""
        guard !url.isEmpty else { return nil }
        return (url, title)
        #else
        return nil
        #endif
    }

    /// Host portion of a URL, with a leading "www." stripped for cleaner matching.
    public static func host(of urlString: String) -> String? {
        guard let host = URLComponents(string: urlString)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
