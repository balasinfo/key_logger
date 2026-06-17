import Foundation

/// What kind of activity a sample represents. Drives the time-quality verdict.
public enum Category: String, Codable, CaseIterable, Sendable {
    case educational   // lectures, tutorials, courses, documentation
    case productive    // coding, writing, work tools
    case news          // news sites / current affairs
    case social        // social media, chat
    case entertainment // movies, comedy, music-for-fun
    case sports        // live sports, highlights
    case games         // foreground game apps
    case unknown
}

/// Whether the time spent looks well-used. This is a heuristic, not a judgement of the person.
public enum Quality: String, Codable, Sendable {
    case wellSpent  // educational / productive
    case neutral    // news, ambiguous
    case wasted     // entertainment / sports / games (the "tell them what they're doing" bucket)
}

/// A single point-in-time observation of the foreground activity. No keystroke content is ever captured.
public struct ActivitySample: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var appName: String
    public var bundleID: String
    public var windowTitle: String?
    public var url: String?
    public var host: String?
    /// e.g. a YouTube video title or detected game name.
    public var detail: String?
    public var category: Category
    public var quality: Quality

    public init(
        timestamp: Date,
        appName: String,
        bundleID: String,
        windowTitle: String? = nil,
        url: String? = nil,
        host: String? = nil,
        detail: String? = nil,
        category: Category,
        quality: Quality
    ) {
        self.timestamp = timestamp
        self.appName = appName
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.url = url
        self.host = host
        self.detail = detail
        self.category = category
        self.quality = quality
    }
}

/// Raw signal handed to the classifier, independent of how it was gathered.
public struct ActivityContext: Sendable {
    public var appName: String
    public var bundleID: String
    public var windowTitle: String?
    public var url: String?
    public var host: String?

    public init(appName: String, bundleID: String, windowTitle: String? = nil, url: String? = nil, host: String? = nil) {
        self.appName = appName
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.url = url
        self.host = host
    }
}
