import XCTest
@testable import ActivityCore

final class ClassifierTests: XCTestCase {
    let c = Classifier(config: .default)

    private func ctx(_ host: String? = nil, title: String? = nil, bundle: String = "com.test.app", app: String = "App") -> ActivityContext {
        ActivityContext(appName: app, bundleID: bundle, windowTitle: title, url: host.map { "https://\($0)/x" }, host: host)
    }

    func testEducationalSite() {
        let r = c.classify(ctx("khanacademy.org"))
        XCTAssertEqual(r.category, .educational)
        XCTAssertEqual(r.quality, .wellSpent)
    }

    func testChatGPTIsProductive() {
        XCTAssertEqual(c.classify(ctx("chatgpt.com")).category, .productive)
    }

    func testNewsIsNeutral() {
        let r = c.classify(ctx("eenadu.net"))
        XCTAssertEqual(r.category, .news)
        XCTAssertEqual(r.quality, .neutral)
    }

    func testYouTubeEducationalByTitle() {
        let r = c.classify(ctx("youtube.com", title: "Calculus Lecture 3 - Derivatives explained"))
        XCTAssertEqual(r.category, .educational)
        XCTAssertEqual(r.quality, .wellSpent)
    }

    func testYouTubePokemonIsEntertainment() {
        let r = c.classify(ctx("youtube.com", title: "Pokemon Season 1 Episode 5"))
        XCTAssertEqual(r.category, .entertainment)
        XCTAssertEqual(r.quality, .wasted)
    }

    func testYouTubeCricketIsSports() {
        let r = c.classify(ctx("youtube.com", title: "India vs Australia cricket highlights"))
        XCTAssertEqual(r.category, .sports)
        XCTAssertEqual(r.quality, .wasted)
    }

    func testYouTubePlainIsEntertainmentFallback() {
        let r = c.classify(ctx("youtube.com", title: "Some random channel upload"))
        XCTAssertEqual(r.category, .entertainment)
    }

    func testGameBundleWins() {
        let r = c.classify(ctx(bundle: "com.valvesoftware.steam", app: "Steam"))
        XCTAssertEqual(r.category, .games)
        XCTAssertEqual(r.quality, .wasted)
    }

    func testUnknownAppIsNeutral() {
        let r = c.classify(ctx(bundle: "com.acme.mystery", app: "Mystery"))
        XCTAssertEqual(r.category, .unknown)
        XCTAssertEqual(r.quality, .neutral)
    }

    func testHostStripsWww() {
        XCTAssertEqual(BrowserInspector.host(of: "https://www.youtube.com/watch?v=abc"), "youtube.com")
    }

    func testConfigOverrideMergesOntoDefaults() throws {
        let tmp = URL(fileURLWithPath: "/tmp/at_cfg_\(UUID().uuidString).json")
        let json = """
        {"hostCategories": {"alerter.online": "productive", "youtube.com": "educational"},
         "educationalKeywords": ["my-custom-keyword"]}
        """
        try json.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let merged = ClassificationConfig.load(from: tmp)
        XCTAssertEqual(merged.hostCategories["alerter.online"], .productive)  // added
        XCTAssertEqual(merged.hostCategories["youtube.com"], .educational)    // re-pointed
        XCTAssertEqual(merged.hostCategories["github.com"], .productive)      // default kept
        XCTAssertTrue(merged.educationalKeywords.contains("my-custom-keyword")) // appended
        XCTAssertTrue(merged.educationalKeywords.contains("lecture"))           // default kept
    }

    func testMissingConfigFallsBackToDefaults() {
        let cfg = ClassificationConfig.load(from: URL(fileURLWithPath: "/tmp/nope_\(UUID().uuidString).json"))
        XCTAssertEqual(cfg.hostCategories["github.com"], .productive)
    }

    func testExpandedHostRules() {
        XCTAssertEqual(c.classify(ctx("mail.google.com")).category, .productive)
        XCTAssertEqual(c.classify(ctx("supabase.com")).category, .productive)
        XCTAssertEqual(c.classify(ctx("leetcode.com")).category, .educational)
        XCTAssertEqual(c.classify(ctx("nytimes.com")).category, .news)
        XCTAssertEqual(c.classify(ctx("espncricinfo.com")).category, .sports)
        XCTAssertEqual(c.classify(ctx("spotify.com")).category, .entertainment)
        XCTAssertEqual(c.classify(ctx("linkedin.com")).category, .social)
        XCTAssertEqual(c.classify(ctx("sh.reddit.com")).category, .social)
    }

    // MARK: - Browser history

    func testHistoryEpochRoundTrips() {
        let ref = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(BrowserHistory.fromChromeTime(BrowserHistory.toChromeTime(ref)).timeIntervalSince1970, ref.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(BrowserHistory.fromSafariTime(BrowserHistory.toSafariTime(ref)).timeIntervalSince1970, ref.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(BrowserHistory.fromFirefoxTime(BrowserHistory.toFirefoxTime(ref)).timeIntervalSince1970, ref.timeIntervalSince1970, accuracy: 0.001)
    }

    func testChromeEpochOffsetIsSane() {
        let year = Calendar(identifier: .gregorian).component(.year, from: BrowserHistory.fromChromeTime(13_335_912_345_000_000))
        XCTAssertTrue(year > 2020 && year < 2030)
    }

    func testHistorySummaryDwellAndClassification() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let visits = [
            HistoryVisit(timestamp: base, url: "https://github.com/x", title: "repo", browser: "Chrome"),
            HistoryVisit(timestamp: base.addingTimeInterval(60), url: "https://youtube.com/x", title: "Calculus lecture", browser: "Firefox"),
            HistoryVisit(timestamp: base.addingTimeInterval(120), url: "https://instagram.com/x", title: "feed", browser: "Safari"),
        ]
        let hs = Reporter(interval: 5).summarizeHistory(visits, classifier: c, tailDwell: 30)
        XCTAssertEqual(hs.totalVisits, 3)
        XCTAssertEqual(hs.topSites.first(where: { $0.host == "github.com" })?.seconds, 60)
        XCTAssertTrue(hs.byCategory.contains { $0.0 == .educational && $0.1 == 60 })
        XCTAssertEqual(hs.estimatedTime, 60 + 60 + 30)
        XCTAssertEqual(hs.byBrowser.count, 3)
        XCTAssertEqual(hs.pages.first?.host, "instagram.com")
        XCTAssertEqual(hs.pages.count, 3)
    }

    func testEmailHtmlIncludesHistorySection() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let hs = Reporter(interval: 5).summarizeHistory(
            [HistoryVisit(timestamp: base, url: "https://github.com/x", title: "repo", browser: "Chrome")],
            classifier: c)
        let summary = Reporter(interval: 5).summarize([])
        let html = EmailReporter.html(summary: summary, periodLabel: "last 2 hours", history: hs)
        XCTAssertTrue(html.contains("Browsing history"))
        XCTAssertTrue(html.contains("github.com"))
        XCTAssertFalse(EmailReporter.html(summary: summary, periodLabel: "last 2 hours").contains("Browsing history"))
    }
}
