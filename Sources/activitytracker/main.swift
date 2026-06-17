import Foundation
import ActivityCore
#if canImport(AppKit)
import AppKit
#endif

let interval: TimeInterval = 5
let defaultRecipient = "dharamarao.bala@manabadi.siliconandhra.org"
func warn(_ msg: String) { FileHandle.standardError.write(Data((msg + "\n").utf8)) }

/// Periodic-email cadence in seconds. `EMAIL_EVERY_HOURS` (e.g. "2", "1.5"); default 2h.
let emailPeriod: TimeInterval = {
    guard let raw = ProcessInfo.processInfo.environment["EMAIL_EVERY_HOURS"] else { return 7200 }
    guard let hours = Double(raw), hours > 0 else {
        warn("ignoring invalid EMAIL_EVERY_HOURS=\(raw); using 2"); return 7200
    }
    return hours * 3600
}()

/// Send only within this closed range of local hours. `EMAIL_WINDOW="START-END"` (24h clock,
/// e.g. "9-21"), or "all" for 0-23; default 9 AM–9 PM.
let emailWindow: ClosedRange<Int> = {
    guard let raw = ProcessInfo.processInfo.environment["EMAIL_WINDOW"]?
        .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return 9...21 }
    if raw.lowercased() == "all" { return 0...23 }
    let parts = raw.split(separator: "-")
    if parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]),
       (0...23).contains(start), (0...23).contains(end), start <= end {
        return start...end
    }
    warn("ignoring invalid EMAIL_WINDOW=\(raw) (want START-END, 0-23); using 9-21")
    return 9...21
}()

/// Human label for the cadence, e.g. "2 hours" / "1 hour" / "1.5 hours".
let cadenceLabel: String = {
    let h = emailPeriod / 3600
    let n = h == h.rounded() ? String(Int(h)) : String(format: "%g", h)
    return h == 1 ? "1 hour" : "\(n) hours"
}()

/// True when `date` falls in the configured send window.
func inEmailWindow(_ date: Date) -> Bool {
    emailWindow.contains(Calendar.current.component(.hour, from: date))
}

func printUsage() {
    print("""
    activitytracker — local macOS activity & time-quality tracker (no keystroke capture)

    USAGE:
      activitytracker track            Run the sampler in the foreground (Ctrl-C to stop).
                                       Emails a periodic report (default every 2h, 9am–9pm) + a
                                       daily summary, each listing all sites browsed, when
                                       RESEND_API_KEY is set. Tune with EMAIL_EVERY_HOURS and
                                       EMAIL_WINDOW (see below).
      activitytracker once             Capture and print a single sample (handy for testing perms)
      activitytracker report [--today|--days N]   Summarize tracked time
                                       (also shows on-disk browsing history for the range)
      activitytracker history [--today|--days N|--hours N]   Browsing history only
                                       (Chrome/Safari/Firefox, current user's own profiles)
      activitytracker notify [--hours N | --daily]   Email a report now
                                       (--hours N: last N hours, default 1; --daily: today so far)
      activitytracker export [--days N] [--out FILE]   Export samples as CSV
      activitytracker purge --days N   Delete samples older than N days
      activitytracker permissions      Show Accessibility/Automation permission status

    Email (Resend): set RESEND_API_KEY in the environment. Optional RESEND_FROM
    (default onboarding@resend.dev) and RESEND_TO (default \(defaultRecipient)).
    Schedule (for `track`): EMAIL_EVERY_HOURS (default 2) and EMAIL_WINDOW="START-END"
    in 24h local hours (default "9-21", or "all" for around the clock).

    Data lives at ~/.activitytracker/activity.sqlite and never leaves this machine
    unless you run `export` or enable email.
    """)
}

/// Build a Resend config from the environment, or nil (with a stderr note) if unconfigured.
func emailConfig() -> EmailReporter.Config? {
    guard let cfg = EmailReporter.Config.fromEnvironment(defaultTo: defaultRecipient) else {
        FileHandle.standardError.write(Data("email disabled: RESEND_API_KEY not set\n".utf8))
        return nil
    }
    return cfg
}

func arg(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}
func flag(_ name: String) -> Bool { CommandLine.arguments.contains(name) }

/// Browsing-history rollup for a window `[since, until)` (until defaults to now), for email.
func historySummary(since: Date, until: Date? = nil) -> Reporter.HistorySummary {
    var visits = BrowserHistory().visits(since: since).visits
    if let until { visits = visits.filter { $0.timestamp < until } }
    return reporter.summarizeHistory(visits, classifier: classifier)
}

/// Print the on-disk browsing-history section: what sites were actually visited (every page
/// load, across Chrome/Safari/Firefox), classified and rolled up. Shared by `report` and `history`.
func printHistory(since: Date, periodLabel: String) {
    let result = BrowserHistory().visits(since: since)
    let hs = reporter.summarizeHistory(result.visits, classifier: classifier)

    print("\nBrowsing history (\(periodLabel)) — on-disk, all profiles of the current user")
    if result.sources.isEmpty && result.errors.isEmpty {
        print("  No readable browser history found (Chrome / Safari / Firefox).")
    }
    if !result.sources.isEmpty {
        let byBrowser = hs.byBrowser.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
        print("  \(hs.totalVisits) pages · est. \(Reporter.format(hs.estimatedTime)) · \(byBrowser)")
    }
    for e in result.errors {
        print("  (\(e.browser): \(e.message))")
    }
    guard hs.totalVisits > 0 else { return }

    print("\n  By category (est. time):")
    for (c, secs) in hs.byCategory {
        print("    \(c.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)) \(Reporter.format(secs))")
    }
    print("\n  Top sites:")
    for s in hs.topSites.prefix(15) {
        let visits = "\(s.visits) visit\(s.visits == 1 ? "" : "s")"
        print("    \(Reporter.format(s.seconds).padding(toLength: 8, withPad: " ", startingAt: 0)) [\(s.category.rawValue)] \(s.host) (\(visits))")
    }
    print("\n  Recent pages:")
    let clock = DateFormatter(); clock.dateFormat = "MMM d HH:mm"
    for p in hs.pages.prefix(15) {
        let label = p.label.count > 70 ? String(p.label.prefix(67)) + "…" : p.label
        print("    \(clock.string(from: p.timestamp))  [\(p.category.rawValue)] \(label) — \(p.host)")
    }
}

func dayLabel(_ date: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateStyle = .medium
    return fmt.string(from: date)
}

func sinceDate() -> Date {
    if flag("--today") {
        return Calendar.current.startOfDay(for: Date())
    }
    if let n = arg("--days").flatMap(Int.init) {
        return Date().addingTimeInterval(-Double(n) * 86_400)
    }
    return Calendar.current.startOfDay(for: Date())
}

let command = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "help"
let classifier = Classifier(config: .load())
let reporter = Reporter(interval: interval)

do {
    switch command {
    case "track":
        let store = try Store()
        print("Tracking every \(Int(interval))s. Data: \(store.path.path)")
        print("This machine is being monitored for activity (apps, websites, video/game titles).")

        // Email, if configured: an hourly report plus a daily summary at local midnight.
        let mailer = emailConfig().map(EmailReporter.init)
        if mailer != nil {
            print("Email reports (every \(cadenceLabel), hours \(emailWindow.lowerBound)–\(emailWindow.upperBound) + daily) -> \(mailer!.config.to)")
        }
        var nextEmail = Date().addingTimeInterval(emailPeriod)
        // Don't fire the daily on first boundary; wait until the calendar day actually rolls over.
        var lastDailyDay = Calendar.current.startOfDay(for: Date())

        Sampler(store: store, classifier: classifier, interval: interval).run(onTick: { now in
            guard let mailer else { return }

            // Periodic: every `emailPeriod`, but only within the configured hour window. Covers
            // the trailing period and includes the sites browsed in it.
            if now >= nextEmail {
                if inEmailWindow(now) {
                    nextEmail = now.addingTimeInterval(emailPeriod)
                    let windowStart = now.addingTimeInterval(-emailPeriod)
                    do {
                        let samples = try store.samples(since: windowStart)
                        try mailer.send(summary: reporter.summarize(samples),
                                        periodLabel: "last \(cadenceLabel)",
                                        history: historySummary(since: windowStart, until: now))
                        print("[\(now)] periodic report emailed (\(samples.count) samples)")
                    } catch {
                        warn("periodic email failed: \(error)")
                    }
                }
                // Outside the window: don't send and don't advance — fires when the window opens.
            }

            // Daily: when the local day rolls over, summarize the day that just ended,
            // including every site browsed across those 24 hours.
            let today = Calendar.current.startOfDay(for: now)
            if today > lastDailyDay {
                let dayStart = lastDailyDay
                lastDailyDay = today
                do {
                    let samples = try store.samples(since: dayStart).filter { $0.timestamp < today }
                    try mailer.send(summary: reporter.summarize(samples),
                                    periodLabel: "daily summary — \(dayLabel(dayStart))",
                                    history: historySummary(since: dayStart, until: today))
                    print("[\(now)] daily report emailed (\(samples.count) samples)")
                } catch {
                    FileHandle.standardError.write(Data("daily email failed: \(error)\n".utf8))
                }
            }
        })

    case "notify":
        guard let mailer = emailConfig().map(EmailReporter.init) else { exit(1) }
        let store = try Store()
        let since: Date
        let label: String
        if flag("--daily") {                       // today so far, from local midnight
            since = Calendar.current.startOfDay(for: Date())
            label = "daily summary — \(dayLabel(since))"
        } else {
            let hours = arg("--hours").flatMap(Double.init) ?? 1
            since = Date().addingTimeInterval(-hours * 3600)
            label = hours == 1 ? "last hour" : "last \(Int(hours)) hours"
        }
        let samples = try store.samples(since: since)
        try mailer.send(summary: reporter.summarize(samples), periodLabel: label,
                        history: historySummary(since: since))
        print("Emailed \(label) report (\(samples.count) samples) to \(mailer.config.to)")

    case "once":
        let store = try Store()
        guard let s = Sampler(store: store, classifier: classifier, interval: interval).sampleOnce() else {
            print("No foreground app detected."); exit(0)
        }
        print("\(s.appName) [\(s.category.rawValue)/\(s.quality.rawValue)] — \(s.detail ?? s.host ?? "—")")

    case "report":
        let store = try Store()
        let summary = reporter.summarize(try store.samples(since: sinceDate()))
        print("Total tracked: \(Reporter.format(summary.total))\n")
        print("By time quality:")
        for (q, secs) in summary.byQuality {
            print("  \(q.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)) \(Reporter.format(secs))")
        }
        print("\nBy category:")
        for (c, secs) in summary.byCategory {
            print("  \(c.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)) \(Reporter.format(secs))")
        }
        print("\nTop activities:")
        for a in summary.topActivities.prefix(15) {
            print("  \(Reporter.format(a.seconds).padding(toLength: 8, withPad: " ", startingAt: 0)) [\(a.category.rawValue)] \(a.label)")
        }
        // Foreground polling only sees the frontmost tab; on-disk history fills in the rest.
        printHistory(since: sinceDate(), periodLabel: flag("--today") ? "today" : "selected range")

    case "history":
        let label: String
        let since: Date
        if let n = arg("--hours").flatMap(Double.init) {
            since = Date().addingTimeInterval(-n * 3600)
            label = n == 1 ? "last hour" : "last \(Int(n)) hours"
        } else {
            since = sinceDate()
            label = flag("--today") || arg("--days") == nil ? "today" : "selected range"
        }
        printHistory(since: since, periodLabel: label)

    case "export":
        let store = try Store()
        let csv = reporter.csv(try store.samples(since: sinceDate()))
        if let out = arg("--out") {
            try csv.write(toFile: out, atomically: true, encoding: .utf8)
            print("Wrote \(out)")
        } else {
            print(csv)
        }

    case "purge":
        guard let days = arg("--days").flatMap(Int.init) else { print("--days N required"); exit(1) }
        let store = try Store()
        print("Deleted \(try store.purge(olderThanDays: days)) samples older than \(days) days.")

    case "permissions":
        #if canImport(AppKit)
        print("Accessibility (window titles): \(AXIsProcessTrusted() ? "granted" : "NOT granted")")
        print("Automation (browser URLs):     granted per-browser on first use (watch for the prompt)")
        if !AXIsProcessTrusted() {
            print("\nEnable in System Settings ▸ Privacy & Security ▸ Accessibility.")
        }
        #endif

    default:
        printUsage()
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
