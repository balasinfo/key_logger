import Foundation
import ActivityCore
#if canImport(AppKit)
import AppKit
#endif

let interval: TimeInterval = 5
let defaultRecipient = "dharamarao.bala@manabadi.siliconandhra.org"
let emailPeriod: TimeInterval = 3600  // hourly

func printUsage() {
    print("""
    activitytracker — local macOS activity & time-quality tracker (no keystroke capture)

    USAGE:
      activitytracker track            Run the sampler in the foreground (Ctrl-C to stop).
                                       Emails hourly + daily reports when RESEND_API_KEY is set.
      activitytracker once             Capture and print a single sample (handy for testing perms)
      activitytracker report [--today|--days N]   Summarize tracked time
      activitytracker notify [--hours N | --daily]   Email a report now
                                       (--hours N: last N hours, default 1; --daily: today so far)
      activitytracker export [--days N] [--out FILE]   Export samples as CSV
      activitytracker purge --days N   Delete samples older than N days
      activitytracker permissions      Show Accessibility/Automation permission status

    Email (Resend): set RESEND_API_KEY in the environment. Optional RESEND_FROM
    (default onboarding@resend.dev) and RESEND_TO (default \(defaultRecipient)).

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
        if mailer != nil { print("Email reports (hourly + daily) -> \(mailer!.config.to)") }
        var nextEmail = Date().addingTimeInterval(emailPeriod)
        // Don't fire the daily on first boundary; wait until the calendar day actually rolls over.
        var lastDailyDay = Calendar.current.startOfDay(for: Date())

        Sampler(store: store, classifier: classifier, interval: interval).run(onTick: { now in
            guard let mailer else { return }

            // Hourly: summary of the trailing hour.
            if now >= nextEmail {
                nextEmail = now.addingTimeInterval(emailPeriod)
                do {
                    let samples = try store.samples(since: now.addingTimeInterval(-emailPeriod))
                    try mailer.send(summary: reporter.summarize(samples), periodLabel: "last hour")
                    print("[\(now)] hourly report emailed (\(samples.count) samples)")
                } catch {
                    FileHandle.standardError.write(Data("hourly email failed: \(error)\n".utf8))
                }
            }

            // Daily: when the local day rolls over, summarize the day that just ended.
            let today = Calendar.current.startOfDay(for: now)
            if today > lastDailyDay {
                let dayStart = lastDailyDay
                lastDailyDay = today
                do {
                    let samples = try store.samples(since: dayStart).filter { $0.timestamp < today }
                    try mailer.send(summary: reporter.summarize(samples),
                                    periodLabel: "daily summary — \(dayLabel(dayStart))")
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
        try mailer.send(summary: reporter.summarize(samples), periodLabel: label)
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
