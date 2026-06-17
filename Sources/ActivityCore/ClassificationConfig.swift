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
        // host substring -> category. Longest match wins (see Classifier.matchHost), so a
        // specific host like "mail.google.com" overrides a broader one. Media hosts
        // (youtube.com, etc.) are re-bucketed by title keywords regardless of what's set here.
        hostCategories: [
            // --- educational: courses, references, coding practice ---
            "youtube.com": .entertainment,   // refined by video title keywords below
            "khanacademy.org": .educational,
            "coursera.org": .educational,
            "udemy.com": .educational,
            "edx.org": .educational,
            "brilliant.org": .educational,
            "duolingo.com": .educational,
            "wikipedia.org": .educational,
            "geeksforgeeks.org": .educational,
            "w3schools.com": .educational,
            "freecodecamp.org": .educational,
            "leetcode.com": .educational,
            "hackerrank.com": .educational,
            "developer.mozilla.org": .educational,
            "arxiv.org": .educational,
            "scholar.google.com": .educational,
            // --- productive: dev tools, work apps, email, AI assistants ---
            "stackoverflow.com": .productive,
            "github.com": .productive,
            "gitlab.com": .productive,
            "bitbucket.org": .productive,
            "supabase.com": .productive,
            "vercel.com": .productive,
            "netlify.com": .productive,
            "console.aws.amazon.com": .productive,
            "cloud.google.com": .productive,
            "portal.azure.com": .productive,
            "npmjs.com": .productive,
            "pypi.org": .productive,
            "huggingface.co": .productive,
            "chatgpt.com": .productive,
            "openai.com": .productive,
            "claude.ai": .productive,
            "gemini.google.com": .productive,
            "perplexity.ai": .productive,
            "docs.google.com": .productive,
            "drive.google.com": .productive,
            "sheets.google.com": .productive,
            "mail.google.com": .productive,
            "outlook.office.com": .productive,
            "outlook.live.com": .productive,
            "notion.so": .productive,
            "linear.app": .productive,
            "atlassian.net": .productive,
            "figma.com": .productive,
            "slack.com": .productive,
            "zoom.us": .productive,
            "meet.google.com": .productive,
            // --- news ---
            "eenadu.net": .news,
            "bbc.com": .news,
            "ndtv.com": .news,
            "nytimes.com": .news,
            "cnn.com": .news,
            "theguardian.com": .news,
            "reuters.com": .news,
            "apnews.com": .news,
            "washingtonpost.com": .news,
            "wsj.com": .news,
            "bloomberg.com": .news,
            "aljazeera.com": .news,
            "thehindu.com": .news,
            "hindustantimes.com": .news,
            "timesofindia.indiatimes.com": .news,
            "indiatimes.com": .news,
            // --- sports ---
            "espn.com": .sports,
            "espncricinfo.com": .sports,
            "cricbuzz.com": .sports,
            "nba.com": .sports,
            "nfl.com": .sports,
            "fifa.com": .sports,
            "skysports.com": .sports,
            // --- entertainment: streaming, music, gossip ---
            "hotstar.com": .entertainment,
            "netflix.com": .entertainment,
            "primevideo.com": .entertainment,
            "disneyplus.com": .entertainment,
            "hulu.com": .entertainment,
            "max.com": .entertainment,
            "twitch.tv": .entertainment,
            "spotify.com": .entertainment,
            "soundcloud.com": .entertainment,
            "imdb.com": .entertainment,
            "sonyliv.com": .entertainment,
            "zee5.com": .entertainment,
            "jiocinema.com": .entertainment,
            "9gag.com": .entertainment,
            "tiktok.com": .entertainment,
            // --- social ---
            "instagram.com": .social,
            "facebook.com": .social,
            "twitter.com": .social,
            "x.com": .social,
            "reddit.com": .social,
            "linkedin.com": .social,
            "web.whatsapp.com": .social,
            "messenger.com": .social,
            "discord.com": .social,
            "snapchat.com": .social,
            "pinterest.com": .social,
            "threads.net": .social,
            "web.telegram.org": .social,
            "quora.com": .social,
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

    /// A partial override read from JSON. Every field is optional, so the file only needs the
    /// rules you want to add or change — anything omitted falls back to the built-in default.
    private struct Override: Codable {
        var hostCategories: [String: Category]?
        var bundleCategories: [String: Category]?
        var educationalKeywords: [String]?
        var entertainmentKeywords: [String]?
        var sportsKeywords: [String]?
    }

    /// Load `~/.activitytracker/classification.json` **merged on top of** `.default`, or just the
    /// defaults if the file is absent/unparseable. Dictionaries merge key-by-key (your entry wins
    /// on a clash); keyword lists are appended to the defaults (deduped). So you can add
    /// `{"hostCategories": {"alerter.online": "productive"}}` without restating every built-in rule.
    /// (Merging can only add or re-point rules, not delete a built-in one.)
    public static func load(from url: URL? = nil) -> ClassificationConfig {
        let path = url ?? defaultPath
        guard let data = try? Data(contentsOf: path),
              let override = try? JSONDecoder().decode(Override.self, from: data)
        else { return .default }
        return .default.merging(override)
    }

    private func merging(_ o: Override) -> ClassificationConfig {
        func dict(_ base: [String: Category], _ ov: [String: Category]?) -> [String: Category] {
            guard let ov else { return base }
            return base.merging(ov) { _, new in new }
        }
        func list(_ base: [String], _ ov: [String]?) -> [String] {
            guard let ov else { return base }
            var seen = Set(base)
            return base + ov.filter { seen.insert($0).inserted }
        }
        return ClassificationConfig(
            hostCategories: dict(hostCategories, o.hostCategories),
            bundleCategories: dict(bundleCategories, o.bundleCategories),
            educationalKeywords: list(educationalKeywords, o.educationalKeywords),
            entertainmentKeywords: list(entertainmentKeywords, o.entertainmentKeywords),
            sportsKeywords: list(sportsKeywords, o.sportsKeywords))
    }

    public static var defaultPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".activitytracker/classification.json")
    }
}
