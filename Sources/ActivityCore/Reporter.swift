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
