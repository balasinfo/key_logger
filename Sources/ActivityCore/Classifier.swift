import Foundation

/// Turns an observed activity into a category + time-quality verdict using the config rules.
/// Pure and deterministic, so it is fully unit-testable without any system permissions.
public struct Classifier: Sendable {
    public let config: ClassificationConfig

    public init(config: ClassificationConfig = .default) {
        self.config = config
    }

    public func classify(_ ctx: ActivityContext) -> (category: Category, quality: Quality, detail: String?) {
        let category = category(for: ctx)
        return (category, quality(for: category), detail(for: ctx, category: category))
    }

    private func category(for ctx: ActivityContext) -> Category {
        // 1. A foreground native app that is a known game / tool wins outright.
        if let bundleHit = matchBundle(ctx.bundleID) {
            return bundleHit
        }

        // 2. Browser tabs: start from the host, then refine media hosts by title keywords.
        if let host = ctx.host, let base = matchHost(host) {
            let titleText = ctx.windowTitle ?? ""
            // YouTube (and other media) get re-bucketed by what is actually being watched.
            if base == .entertainment || host.contains("youtube.com") {
                return refineMedia(titleText, fallback: base)
            }
            return base
        }

        // 3. Non-browser app with no rule: try keywords on the window title, else unknown.
        if let title = ctx.windowTitle, !title.isEmpty {
            return refineMedia(title, fallback: .unknown)
        }
        return .unknown
    }

    /// Re-classify media/ambiguous content by keyword vote on its title.
    private func refineMedia(_ text: String, fallback: Category) -> Category {
        let lower = text.lowercased()
        if config.educationalKeywords.contains(where: lower.contains) { return .educational }
        if config.sportsKeywords.contains(where: lower.contains) { return .sports }
        if config.entertainmentKeywords.contains(where: lower.contains) { return .entertainment }
        return fallback
    }

    private func matchBundle(_ bundleID: String) -> Category? {
        let lower = bundleID.lowercased()
        // Longest substring match first for stability.
        for key in config.bundleCategories.keys.sorted(by: { $0.count > $1.count }) {
            if lower.contains(key.lowercased()) { return config.bundleCategories[key] }
        }
        return nil
    }

    private func matchHost(_ host: String) -> Category? {
        let lower = host.lowercased()
        for key in config.hostCategories.keys.sorted(by: { $0.count > $1.count }) {
            if lower.contains(key.lowercased()) { return config.hostCategories[key] }
        }
        return nil
    }

    private func quality(for category: Category) -> Quality {
        switch category {
        case .educational, .productive: return .wellSpent
        case .news, .unknown: return .neutral
        case .social, .entertainment, .sports, .games: return .wasted
        }
    }

    /// Human-readable "what they are doing" string for reports.
    private func detail(for ctx: ActivityContext, category: Category) -> String? {
        if let title = ctx.windowTitle, !title.isEmpty { return title }
        if let host = ctx.host { return host }
        return ctx.appName
    }
}
