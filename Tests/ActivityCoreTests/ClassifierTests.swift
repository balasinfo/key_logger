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
}
