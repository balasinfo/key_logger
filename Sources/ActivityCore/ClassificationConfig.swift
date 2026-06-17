import Foundation

/// User-tunable rules for classification. Everything is data so the user can adjust
/// "what counts as well-spent" without touching code. Loaded from JSON when present,
/// otherwise sensible defaults are used.
public struct ClassificationConfig: Codable, Sendable {
    /// host substring -> category. First match wins, longest host first.
    public var hostCategories: [String: Category]
    /// bundle-ID substring -> category (e.g. game launchers, IDEs).
    public var bundleCategories: [String: Category]
    /// Title/keyword buckets used mainly to split YouTube and other media into good vs bad.
    public var educationalKeywords: [String]
    public var entertainmentKeywords: [String]
    public var sportsKeywords: [String]

    public init(
        hostCategories: [String: Category],
        bundleCategories: [String: Category],
        educationalKeywords: [String],
        entertainmentKeywords: [String],
        sportsKeywords: [String]
    ) {
        self.hostCategories = hostCategories
        self.bundleCategories = bundleCategories
        self.educationalKeywords = educationalKeywords
        self.entertainmentKeywords = entertainmentKeywords
        self.sportsKeywords = sportsKeywords
    }

    public static let `default` = ClassificationConfig(
        hostCategories: [
            "youtube.com": .entertainment,   // refined by video title keywords below
            "khanacademy.org": .educational,
            "coursera.org": .educational,
            "udemy.com": .educational,
            "edx.org": .educational,
            "wikipedia.org": .educational,
            "stackoverflow.com": .productive,
            "github.com": .productive,
            "chatgpt.com": .productive,
            "openai.com": .productive,
            "claude.ai": .productive,
            "docs.google.com": .productive,
            "eenadu.net": .news,
            "bbc.com": .news,
            "ndtv.com": .news,
            "espn.com": .sports,
            "cricbuzz.com": .sports,
            "hotstar.com": .entertainment,
            "netflix.com": .entertainment,
            "primevideo.com": .entertainment,
            "instagram.com": .social,
            "facebook.com": .social,
            "twitter.com": .social,
            "x.com": .social,
            "reddit.com": .social,
            "tiktok.com": .entertainment,
        ],
        bundleCategories: [
            "com.apple.dt.Xcode": .productive,
            "com.microsoft.VSCode": .productive,
            "com.jetbrains": .productive,        // IntelliJ, PyCharm, etc.
            "com.apple.Terminal": .productive,
            "com.googlecode.iterm2": .productive,
            "com.apple.dt.playground": .productive,
            "com.valvesoftware.steam": .games,
            "com.epicgames": .games,
            "com.riotgames": .games,
            "com.mojang": .games,        // Minecraft
            "com.blizzard": .games,
            "com.innersloth.amongus": .games,
        ],
        educationalKeywords: [
            "lecture", "tutorial", "course", "lesson", "exam", "study", "how to",
            "explained", "documentary", "physics", "chemistry", "math", "biology",
            "history", "programming", "coding", "interview prep", "gate ", "jee", "neet",
        ],
        entertainmentKeywords: [
            "movie", "trailer", "comedy", "funny", "prank", "vlog", "song", "music video",
            "pokemon", "pokémon", "cartoon", "anime", "web series", "reaction", "meme",
        ],
        sportsKeywords: [
            "cricket", "football", "ipl", "highlights", "match", "vs ", "goal", "fifa",
            "nba", "tournament", "wwe", "ufc",
        ]
    )

    /// Load from `~/.activitytracker/classification.json` if present, else defaults.
    public static func load(from url: URL? = nil) -> ClassificationConfig {
        let path = url ?? defaultPath
        guard let data = try? Data(contentsOf: path),
              let cfg = try? JSONDecoder().decode(ClassificationConfig.self, from: data)
        else { return .default }
        return cfg
    }

    public static var defaultPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".activitytracker/classification.json")
    }
}
