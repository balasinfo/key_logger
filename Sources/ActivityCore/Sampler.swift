import Foundation
#if canImport(AppKit)
import AppKit
import ApplicationServices
#endif

/// Periodically observes the foreground app (and, for browsers, the active tab) and
/// writes a classified sample to the store. Polling — not an event tap — so it needs
/// no input-monitoring entitlement; reading window titles uses Accessibility (read-only).
public final class Sampler {
    private let store: Store
    private let classifier: Classifier
    private let inspector: BrowserInspector
    private let interval: TimeInterval

    public init(store: Store, classifier: Classifier, interval: TimeInterval = 5) {
        self.store = store
        self.classifier = classifier
        self.inspector = BrowserInspector()
        self.interval = interval
    }

    /// Capture exactly one sample now. Returns nil if nothing is in the foreground.
    public func sampleOnce(now: Date = Date()) -> ActivitySample? {
        #if canImport(AppKit)
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appName = app.localizedName ?? "Unknown"
        let bundleID = app.bundleIdentifier ?? "unknown"

        var url: String?
        var host: String?
        var windowTitle: String?

        if BrowserInspector.isSupportedBrowser(bundleID: bundleID),
           let tab = inspector.activeTab(bundleID: bundleID) {
            url = tab.url
            host = BrowserInspector.host(of: tab.url)
            windowTitle = tab.title
        } else {
            windowTitle = Sampler.focusedWindowTitle(pid: app.processIdentifier)
        }

        let ctx = ActivityContext(
            appName: appName, bundleID: bundleID,
            windowTitle: windowTitle, url: url, host: host
        )
        let result = classifier.classify(ctx)
        return ActivitySample(
            timestamp: now,
            appName: appName, bundleID: bundleID,
            windowTitle: windowTitle, url: url, host: host,
            detail: result.detail,
            category: result.category, quality: result.quality
        )
        #else
        return nil
        #endif
    }

    /// Run forever, sampling every `interval` seconds. Pauses are honored via `isPaused`.
    /// `onTick` fires once per cycle (after the sample is stored) so callers can drive
    /// periodic side effects like the hourly email without the sampler knowing about them.
    public func run(isPaused: @escaping () -> Bool = { false }, onTick: ((Date) -> Void)? = nil) {
        while true {
            let now = Date()
            if !isPaused(), let sample = sampleOnce(now: now) {
                do { try store.insert(sample) }
                catch { FileHandle.standardError.write(Data("store error: \(error)\n".utf8)) }
            }
            onTick?(now)
            Thread.sleep(forTimeInterval: interval)
        }
    }

    /// Title of the focused window of `pid` via the Accessibility API (read-only).
    /// Returns nil when Accessibility permission is not granted.
    static func focusedWindowTitle(pid: pid_t) -> String? {
        #if canImport(AppKit)
        guard AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        var window: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window else { return nil }
        var title: AnyObject?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success
        else { return nil }
        return title as? String
        #else
        return nil
        #endif
    }
}
