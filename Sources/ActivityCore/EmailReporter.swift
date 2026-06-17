import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends activity summaries by email through the Resend HTTP API (https://resend.com).
/// The API key is read from the environment (`RESEND_API_KEY`) and never stored on disk.
public struct EmailReporter {
    public struct Config: Sendable {
        public var apiKey: String
        public var from: String
        public var to: String
        public init(apiKey: String, from: String, to: String) {
            self.apiKey = apiKey
            self.from = from
            self.to = to
        }

        /// Build from environment + defaults. Returns nil if no API key is configured.
        /// RESEND_API_KEY (required), RESEND_FROM, RESEND_TO override the defaults.
        public static func fromEnvironment(
            defaultFrom: String = "onboarding@resend.dev",
            defaultTo: String
        ) -> Config? {
            let env = ProcessInfo.processInfo.environment
            guard let key = env["RESEND_API_KEY"], !key.isEmpty else { return nil }
            return Config(
                apiKey: key,
                from: env["RESEND_FROM"] ?? defaultFrom,
                to: env["RESEND_TO"] ?? defaultTo
            )
        }
    }

    public let config: Config
    private let endpoint = URL(string: "https://api.resend.com/emails")!

    public init(config: Config) { self.config = config }

    /// Render + send a summary for the given period. Throws on transport / API error.
    public func send(summary: Reporter.Summary, periodLabel: String) throws {
        let subject = "Activity report — \(periodLabel)"
        let html = EmailReporter.html(summary: summary, periodLabel: periodLabel)
        try send(subject: subject, html: html)
    }

    public func send(subject: String, html: String) throws {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "from": config.from,
            "to": [config.to],
            "subject": subject,
            "html": html,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // CLI context: block on the async request with a semaphore.
        let sem = DispatchSemaphore(value: 0)
        var result: Result<Void, Error> = .failure(EmailError.noResponse)
        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            defer { sem.signal() }
            if let error { result = .failure(error); return }
            guard let http = response as? HTTPURLResponse else {
                result = .failure(EmailError.noResponse); return
            }
            if (200..<300).contains(http.statusCode) {
                result = .success(())
            } else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                result = .failure(EmailError.api(status: http.statusCode, body: body))
            }
        }
        task.resume()
        sem.wait()
        try result.get()
    }

    /// Pure HTML renderer — no network, so it is unit-testable.
    public static func html(summary: Reporter.Summary, periodLabel: String) -> String {
        func row(_ label: String, _ secs: TimeInterval, _ color: String = "#333") -> String {
            "<tr><td style=\"padding:4px 12px 4px 0;color:\(color)\">\(esc(label))</td>"
            + "<td style=\"padding:4px 0;text-align:right\">\(Reporter.format(secs))</td></tr>"
        }
        let qualityColor: [Quality: String] = [.wellSpent: "#2e7d32", .neutral: "#888", .wasted: "#c62828"]

        let qualityRows = summary.byQuality
            .map { row($0.0.rawValue, $0.1, qualityColor[$0.0] ?? "#333") }
            .joined()
        let categoryRows = summary.byCategory.map { row($0.0.rawValue, $0.1) }.joined()
        let activityRows = summary.topActivities.prefix(15)
            .map { "<tr><td style=\"padding:4px 12px 4px 0\">\(esc($0.label)) "
                 + "<span style=\"color:#999\">[\(esc($0.category.rawValue))]</span></td>"
                 + "<td style=\"padding:4px 0;text-align:right\">\(Reporter.format($0.seconds))</td></tr>" }
            .joined()

        return """
        <div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:560px">
          <h2 style="margin:0 0 4px">Activity report</h2>
          <p style="color:#666;margin:0 0 16px">\(esc(periodLabel)) · total tracked \(Reporter.format(summary.total))</p>
          <h3 style="margin:16px 0 4px">Time quality</h3>
          <table style="border-collapse:collapse;width:100%">\(qualityRows)</table>
          <h3 style="margin:16px 0 4px">By category</h3>
          <table style="border-collapse:collapse;width:100%">\(categoryRows)</table>
          <h3 style="margin:16px 0 4px">Top activities</h3>
          <table style="border-collapse:collapse;width:100%">\(activityRows)</table>
          <p style="color:#aaa;font-size:12px;margin-top:20px">
            Sent by activitytracker. Window/app/site metadata only — no keystrokes captured.</p>
        </div>
        """
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}

public enum EmailError: Error, CustomStringConvertible {
    case noResponse
    case api(status: Int, body: String)
    case notConfigured

    public var description: String {
        switch self {
        case .noResponse: return "no response from email service"
        case .api(let status, let body): return "email API error \(status): \(body)"
        case .notConfigured: return "RESEND_API_KEY is not set — see CLAUDE.md for setup"
        }
    }
}
