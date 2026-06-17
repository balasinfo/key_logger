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

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
