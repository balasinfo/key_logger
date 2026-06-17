// Plain-main test harness (no XCTest), runnable via ./test.sh under bare Command Line Tools.
// The XCTest version lives in Tests/ActivityCoreTests and runs via `swift test` when full Xcode
// is installed. Keep the two in sync.
import ActivityCore
import Foundation

var failures = 0
func check(_ name: String, _ cond: Bool) {
    print((cond ? "  ok  " : " FAIL ") + name); if !cond { failures += 1 }
}

let c = Classifier(config: .default)
func ctx(_ host: String? = nil, title: String? = nil, bundle: String = "com.test.app") -> ActivityContext {
    ActivityContext(appName: "App", bundleID: bundle, windowTitle: title,
                    url: host.map { "https://\($0)/x" }, host: host)
}

check("khanacademy -> educational/wellSpent",
      { let r = c.classify(ctx("khanacademy.org")); return r.category == .educational && r.quality == .wellSpent }())
check("chatgpt -> productive", c.classify(ctx("chatgpt.com")).category == .productive)
check("eenadu -> news/neutral",
      { let r = c.classify(ctx("eenadu.net")); return r.category == .news && r.quality == .neutral }())
check("YouTube lecture -> educational",
      c.classify(ctx("youtube.com", title: "Calculus Lecture 3 explained")).category == .educational)
check("YouTube pokemon -> entertainment/wasted",
      { let r = c.classify(ctx("youtube.com", title: "Pokemon Episode 5")); return r.category == .entertainment && r.quality == .wasted }())
check("YouTube cricket -> sports",
      c.classify(ctx("youtube.com", title: "India vs Australia cricket highlights")).category == .sports)
check("YouTube plain -> entertainment fallback",
      c.classify(ctx("youtube.com", title: "random upload")).category == .entertainment)
check("steam bundle -> games/wasted",
      { let r = c.classify(ctx(bundle: "com.valvesoftware.steam")); return r.category == .games && r.quality == .wasted }())
check("jetbrains -> productive", c.classify(ctx(bundle: "com.jetbrains.intellij")).category == .productive)
check("unknown -> neutral", c.classify(ctx(bundle: "com.acme.mystery")).quality == .neutral)
check("host strips www", BrowserInspector.host(of: "https://www.youtube.com/watch?v=abc") == "youtube.com")
// Expanded default host rules.
check("gmail -> productive", c.classify(ctx("mail.google.com")).category == .productive)
check("supabase -> productive", c.classify(ctx("supabase.com")).category == .productive)
check("leetcode -> educational", c.classify(ctx("leetcode.com")).category == .educational)
check("nytimes -> news", c.classify(ctx("nytimes.com")).category == .news)
check("espncricinfo -> sports", c.classify(ctx("espncricinfo.com")).category == .sports)
check("spotify -> entertainment", c.classify(ctx("spotify.com")).category == .entertainment)
check("linkedin -> social", c.classify(ctx("linkedin.com")).category == .social)
check("sh.reddit subdomain -> social", c.classify(ctx("sh.reddit.com")).category == .social)

// Store round-trip + reporter on a throwaway DB.
do {
    let tmp = URL(fileURLWithPath: "/tmp/at_test_\(UUID().uuidString).sqlite")
    let store = try Store(path: tmp)
    let s = c.classify(ctx("youtube.com", title: "Physics lecture"))
    try store.insert(ActivitySample(timestamp: Date(), appName: "Chrome", bundleID: "com.google.Chrome",
        windowTitle: "Physics lecture", url: "https://youtube.com/x", host: "youtube.com",
        detail: s.detail, category: s.category, quality: s.quality))
    let back = try store.samples(since: Date().addingTimeInterval(-60))
    check("store round-trip count", back.count == 1)
    check("store round-trip category", back.first?.category == .educational)
    let rep = Reporter(interval: 5)
    let summary = rep.summarize(back)
    check("reporter total", summary.total == 5)
    check("csv has header", rep.csv(back).hasPrefix("timestamp,app"))

    // Email HTML rendering is pure — exercise it without sending.
    let html = EmailReporter.html(summary: summary, periodLabel: "last hour")
    check("email html has report heading", html.contains("Activity report"))
    check("email html shows category", html.contains("educational"))
    check("email html escapes nothing odd", !html.contains("<script"))
    check("email config nil without key",
          EmailReporter.Config.fromEnvironment(defaultTo: "x@y.z") == nil
            || ProcessInfo.processInfo.environment["RESEND_API_KEY"] != nil)
    try? FileManager.default.removeItem(at: tmp)
} catch {
    check("store round-trip threw: \(error)", false)
}

// Config override merges onto defaults (adds/re-points rules; keeps the rest).
do {
    let tmp = URL(fileURLWithPath: "/tmp/at_cfg_\(UUID().uuidString).json")
    let json = """
    {"hostCategories": {"alerter.online": "productive", "youtube.com": "educational"},
     "educationalKeywords": ["my-custom-keyword"]}
    """
    try json.write(to: tmp, atomically: true, encoding: .utf8)
    let merged = ClassificationConfig.load(from: tmp)
    let mc = Classifier(config: merged)
    check("merge adds new host", mc.classify(ctx("alerter.online")).category == .productive)
    check("merge re-points existing host", merged.hostCategories["youtube.com"] == .educational)
    check("merge keeps default hosts", mc.classify(ctx("github.com")).category == .productive)
    check("merge appends keywords", merged.educationalKeywords.contains("my-custom-keyword"))
    check("merge keeps default keywords", merged.educationalKeywords.contains("lecture"))
    check("missing file falls back to defaults",
          ClassificationConfig.load(from: URL(fileURLWithPath: "/tmp/nope_\(UUID().uuidString).json")).hostCategories["github.com"] == .productive)
    try? FileManager.default.removeItem(at: tmp)
}

// Browser-history epoch conversions are pure — round-trip them against a known instant.
do {
    let ref = Date(timeIntervalSince1970: 1_700_000_000)
    check("chrome time round-trips",
          abs(BrowserHistory.fromChromeTime(BrowserHistory.toChromeTime(ref)).timeIntervalSince(ref)) < 0.001)
    check("safari time round-trips",
          abs(BrowserHistory.fromSafariTime(BrowserHistory.toSafariTime(ref)).timeIntervalSince(ref)) < 0.001)
    check("firefox time round-trips",
          abs(BrowserHistory.fromFirefoxTime(BrowserHistory.toFirefoxTime(ref)).timeIntervalSince(ref)) < 0.001)
    // A real Chrome stamp (13335912345000000 µs since 1601) lands in 2023, not 1601/1970.
    let y = Calendar(identifier: .gregorian).component(.year,
                from: BrowserHistory.fromChromeTime(13_335_912_345_000_000))
    check("chrome epoch offset is sane", y > 2020 && y < 2030)
}

// History aggregation: dwell estimated from the gap to the next visit, capped.
do {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let visits = [
        HistoryVisit(timestamp: base, url: "https://github.com/x", title: "repo", browser: "Chrome"),
        HistoryVisit(timestamp: base.addingTimeInterval(60), url: "https://youtube.com/x",
                     title: "Calculus lecture", browser: "Firefox"),
        HistoryVisit(timestamp: base.addingTimeInterval(120), url: "https://instagram.com/x",
                     title: "feed", browser: "Safari"),
    ]
    let hs = Reporter(interval: 5).summarizeHistory(visits, classifier: c, tailDwell: 30)
    check("history counts all visits", hs.totalVisits == 3)
    check("history github dwell = 60s", hs.topSites.first(where: { $0.host == "github.com" })?.seconds == 60)
    check("history youtube lecture is educational",
          hs.byCategory.contains { $0.0 == .educational && $0.1 == 60 })
    check("history tail dwell applied", hs.estimatedTime == 60 + 60 + 30)
    check("history groups by browser", hs.byBrowser.count == 3)
    check("history pages newest first", hs.pages.first?.host == "instagram.com")
    check("history pages includes all", hs.pages.count == 3)

    // Email HTML includes the browsing-history section when a history summary is passed.
    let emptySummary = Reporter(interval: 5).summarize([])
    let withHistory = EmailReporter.html(summary: emptySummary, periodLabel: "last 2 hours", history: hs)
    check("email shows history heading", withHistory.contains("Browsing history"))
    check("email lists a browsed site", withHistory.contains("github.com"))
    check("email omits history when nil",
          !EmailReporter.html(summary: emptySummary, periodLabel: "last 2 hours").contains("Browsing history"))
}

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
