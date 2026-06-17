import Foundation

/// Aggregates raw samples into time-per-category / time-per-site summaries.
/// Each sample stands for roughly `interval` seconds of elapsed time.
public struct Reporter {
    public let interval: TimeInterval
    public init(interval: TimeInterval = 5) { self.interval = interval }

    public struct Summary {
        public var byCategory: [(Category, TimeInterval)]
        public var byQuality: [(Quality, TimeInterval)]
        public var topActivities: [(label: String, category: Category, seconds: TimeInterval)]
        public var total: TimeInterval
    }

    public func summarize(_ samples: [ActivitySample]) -> Summary {
        var cat: [Category: TimeInterval] = [:]
        var qual: [Quality: TimeInterval] = [:]
        var activity: [String: (Category, TimeInterval)] = [:]

        for s in samples {
            cat[s.category, default: 0] += interval
            qual[s.quality, default: 0] += interval
            let label = s.detail ?? s.host ?? s.appName
            let prev = activity[label] ?? (s.category, 0)
            activity[label] = (s.category, prev.1 + interval)
        }

        return Summary(
            byCategory: cat.sorted { $0.value > $1.value },
            byQuality: qual.sorted { $0.value > $1.value },
            topActivities: activity
                .map { (label: $0.key, category: $0.value.0, seconds: $0.value.1) }
                .sorted { $0.seconds > $1.seconds },
            total: Double(samples.count) * interval
        )
    }

    /// Aggregated view of on-disk browsing history (a different signal from the foreground poll:
    /// every page load, not just the frontmost tab). Time is *estimated* — see `summarizeHistory`.
    public struct HistorySummary {
        public var byCategory: [(Category, TimeInterval)]
        public var byQuality: [(Quality, TimeInterval)]
        public var topSites: [(host: String, category: Category, visits: Int, seconds: TimeInterval)]
        /// Every visited page, newest first. Callers cap as needed (CLI ~15, email more).
        public var pages: [(timestamp: Date, label: String, host: String, category: Category)]
        public var byBrowser: [(String, Int)]
        public var totalVisits: Int
        public var estimatedTime: TimeInterval
    }

    /// Classify each visit and roll history up by category / site / browser.
    ///
    /// History records *when* a page was opened, not how long it was read, so per-page time is
    /// estimated as the gap until the next visit (any browser), clamped to `maxDwell` so an
    /// idle/overnight gap doesn't balloon. The final, still-open page gets `tailDwell`. This is a
    /// rough proxy, deliberately labelled "est." in the report — visit counts are exact.
    public func summarizeHistory(_ visits: [HistoryVisit], classifier: Classifier,
                                 maxDwell: TimeInterval = 1800, tailDwell: TimeInterval = 120) -> HistorySummary {
        let sorted = visits.sorted { $0.timestamp < $1.timestamp }
        var cat: [Category: TimeInterval] = [:]
        var qual: [Quality: TimeInterval] = [:]
        var sites: [String: (Category, Int, TimeInterval)] = [:]
        var browsers: [String: Int] = [:]
        var pages: [(Date, String, String, Category)] = []
        var estimated: TimeInterval = 0

        for (i, v) in sorted.enumerated() {
            let dwell = i + 1 < sorted.count
                ? min(max(sorted[i + 1].timestamp.timeIntervalSince(v.timestamp), 0), maxDwell)
                : tailDwell
            let host = BrowserInspector.host(of: v.url) ?? v.url
            let ctx = ActivityContext(appName: v.browser, bundleID: "",
                                      windowTitle: v.title, url: v.url, host: host)
            let r = classifier.classify(ctx)

            cat[r.category, default: 0] += dwell
            qual[r.quality, default: 0] += dwell
            let prev = sites[host] ?? (r.category, 0, 0)
            sites[host] = (r.category, prev.1 + 1, prev.2 + dwell)
            browsers[v.browser, default: 0] += 1
            estimated += dwell
            pages.append((v.timestamp, v.title ?? host, host, r.category))
        }

        return HistorySummary(
            byCategory: cat.sorted { $0.value > $1.value },
            byQuality: qual.sorted { $0.value > $1.value },
            topSites: sites
                .map { (host: $0.key, category: $0.value.0, visits: $0.value.1, seconds: $0.value.2) }
                .sorted { $0.seconds > $1.seconds },
            pages: pages.reversed()
                .map { (timestamp: $0.0, label: $0.1, host: $0.2, category: $0.3) },
            byBrowser: browsers.sorted { $0.value > $1.value },
            totalVisits: sorted.count,
            estimatedTime: estimated)
    }

    /// CSV for `export`. Header + one row per sample.
    public func csv(_ samples: [ActivitySample]) -> String {
        let iso = ISO8601DateFormatter()
        var lines = ["timestamp,app,bundle_id,host,category,quality,detail"]
        for s in samples {
            let cols = [
                iso.string(from: s.timestamp), s.appName, s.bundleID,
                s.host ?? "", s.category.rawValue, s.quality.rawValue, s.detail ?? "",
            ].map(Reporter.escapeCSV)
            lines.append(cols.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func escapeCSV(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}
