import Foundation
import SQLite3

/// One page-load recorded in a browser's on-disk history.
public struct HistoryVisit: Sendable, Equatable {
    public var timestamp: Date
    public var url: String
    public var title: String?
    public var browser: String

    public init(timestamp: Date, url: String, title: String? = nil, browser: String) {
        self.timestamp = timestamp
        self.url = url
        self.title = title
        self.browser = browser
    }
}

/// Reads the **current macOS user's** on-disk browsing history across installed browsers
/// (Chrome, Safari, Firefox) so the report can show *what sites were actually visited* — the
/// 5s foreground poll only ever sees the frontmost tab.
///
/// This is read-only and strictly scoped:
/// - Only the current user's own profiles under `~/Library` are read — never other users.
/// - Private/incognito windows write nothing to disk, so there is nothing of theirs to read.
/// - Each history DB is copied to a temp file and opened **read-only**; the originals are never
///   touched (also dodges the "database is locked" you get from a running browser's WAL file).
///
/// Adding a Chromium-family browser (Edge, Brave, Arc) = add another root to `chromeRoots`.
public struct BrowserHistory {
    /// A source we tried to read but couldn't (e.g. Safari without Full Disk Access).
    public struct SourceError: Sendable {
        public let browser: String
        public let message: String
    }

    public struct Result: Sendable {
        public var visits: [HistoryVisit]
        public var sources: [String]      // browsers we successfully read at least one profile from
        public var errors: [SourceError]  // browsers present but unreadable
    }

    private let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// All visits at or after `since`, across every installed/readable browser profile,
    /// merged and sorted by time.
    public func visits(since: Date) -> Result {
        let fm = FileManager.default
        var all: [HistoryVisit] = []
        var sources: [String] = []
        var errors: [SourceError] = []

        func note(source: String) { if !sources.contains(source) { sources.append(source) } }

        // --- Chrome (and any other Chromium roots) -----------------------------------------
        // `urls.last_visit_time`/`visits.visit_time` are microseconds since 1601-01-01 UTC.
        let chromeSQL = """
            SELECT urls.url, urls.title, visits.visit_time
            FROM visits JOIN urls ON urls.id = visits.url
            WHERE visits.visit_time >= ?
            ORDER BY visits.visit_time ASC;
        """
        let chromeRoots = [home.appendingPathComponent("Library/Application Support/Google/Chrome")]
        for root in chromeRoots {
            for profile in chromiumProfiles(in: root) {
                let db = profile.appendingPathComponent("History")
                guard fm.fileExists(atPath: db.path) else { continue }
                do {
                    all += try read(db: db, browser: "Chrome", sql: chromeSQL,
                                    threshold: BrowserHistory.toChromeTime(since),
                                    convert: BrowserHistory.fromChromeTime)
                    note(source: "Chrome")
                } catch {
                    errors.append(SourceError(browser: "Chrome (\(profile.lastPathComponent))",
                                              message: "\(error)"))
                }
            }
        }

        // --- Safari -------------------------------------------------------------------------
        // `visit_time` is CFAbsoluteTime: seconds since 2001-01-01. Needs Full Disk Access.
        let safari = home.appendingPathComponent("Library/Safari/History.db")
        if fm.fileExists(atPath: safari.path) {
            let sql = """
                SELECT hi.url, hv.title, hv.visit_time
                FROM history_visits hv JOIN history_items hi ON hi.id = hv.history_item
                WHERE hv.visit_time >= ?
                ORDER BY hv.visit_time ASC;
            """
            do {
                all += try read(db: safari, browser: "Safari", sql: sql,
                                threshold: BrowserHistory.toSafariTime(since),
                                convert: BrowserHistory.fromSafariTime)
                note(source: "Safari")
            } catch {
                errors.append(SourceError(
                    browser: "Safari",
                    message: "unreadable — give your terminal Full Disk Access "
                        + "(System Settings ▸ Privacy & Security ▸ Full Disk Access)."))
            }
        }

        // --- Firefox ------------------------------------------------------------------------
        // `moz_historyvisits.visit_date` is microseconds since 1970-01-01 UTC.
        let ffRoot = home.appendingPathComponent("Library/Application Support/Firefox/Profiles")
        let ffSQL = """
            SELECT p.url, p.title, h.visit_date
            FROM moz_historyvisits h JOIN moz_places p ON p.id = h.place_id
            WHERE h.visit_date >= ?
            ORDER BY h.visit_date ASC;
        """
        if let profiles = try? fm.contentsOfDirectory(at: ffRoot, includingPropertiesForKeys: nil) {
            for profile in profiles {
                let db = profile.appendingPathComponent("places.sqlite")
                guard fm.fileExists(atPath: db.path) else { continue }
                do {
                    all += try read(db: db, browser: "Firefox", sql: ffSQL,
                                    threshold: BrowserHistory.toFirefoxTime(since),
                                    convert: BrowserHistory.fromFirefoxTime)
                    note(source: "Firefox")
                } catch {
                    errors.append(SourceError(browser: "Firefox (\(profile.lastPathComponent))",
                                              message: "\(error)"))
                }
            }
        }

        return Result(visits: all.sorted { $0.timestamp < $1.timestamp },
                      sources: sources, errors: errors)
    }

    // MARK: - Profile discovery

    /// Chromium keeps each profile in its own subdir ("Default", "Profile 1", …) under the
    /// app-support root. We treat any subdir that actually contains a `History` file as a profile.
    private func chromiumProfiles(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return entries.filter { fm.fileExists(atPath: $0.appendingPathComponent("History").path) }
    }

    // MARK: - SQLite read (on a read-only temp copy)

    private func read(db dbURL: URL, browser: String, sql: String,
                      threshold: Double, convert: (Double) -> Date) throws -> [HistoryVisit] {
        let (copy, cleanup) = try copyForReading(dbURL)
        defer { cleanup() }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw HistoryError.open(msg)
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw HistoryError.query(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, threshold)

        var out: [HistoryVisit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let urlC = sqlite3_column_text(stmt, 0) else { continue }
            let url = String(cString: urlC)
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let raw = sqlite3_column_double(stmt, 2)
            out.append(HistoryVisit(timestamp: convert(raw), url: url, title: title, browser: browser))
        }
        return out
    }

    /// Copy a (possibly WAL-backed, possibly in-use) DB plus its `-wal`/`-shm` sidecars into a
    /// throwaway temp dir so we can open it read-only without disturbing the browser. Returns the
    /// copy's path and a cleanup closure.
    private func copyForReading(_ original: URL) throws -> (URL, () -> Void) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("activitytracker-history-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let cleanup: () -> Void = { try? fm.removeItem(at: dir) }

        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: original.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            do {
                try fm.copyItem(at: src, to: dir.appendingPathComponent(src.lastPathComponent))
            } catch where suffix != "" {
                // Sidecars are optional; only a missing/locked main file is fatal.
            }
        }
        let main = dir.appendingPathComponent(original.lastPathComponent)
        guard fm.fileExists(atPath: main.path) else {
            cleanup()
            throw HistoryError.open("could not copy \(original.lastPathComponent)")
        }
        return (main, cleanup)
    }

    // MARK: - Epoch conversions (pure, unit-tested)

    public static let chromeEpochOffset = 11_644_473_600.0   // 1601-01-01 → 1970-01-01, seconds
    public static let safariEpochOffset =    978_307_200.0   // 1970-01-01 → 2001-01-01, seconds

    public static func fromChromeTime(_ micros: Double) -> Date {
        Date(timeIntervalSince1970: micros / 1_000_000 - chromeEpochOffset)
    }
    public static func toChromeTime(_ date: Date) -> Double {
        (date.timeIntervalSince1970 + chromeEpochOffset) * 1_000_000
    }
    public static func fromSafariTime(_ seconds: Double) -> Date {
        Date(timeIntervalSince1970: seconds + safariEpochOffset)
    }
    public static func toSafariTime(_ date: Date) -> Double {
        date.timeIntervalSince1970 - safariEpochOffset
    }
    public static func fromFirefoxTime(_ micros: Double) -> Date {
        Date(timeIntervalSince1970: micros / 1_000_000)
    }
    public static func toFirefoxTime(_ date: Date) -> Double {
        date.timeIntervalSince1970 * 1_000_000
    }
}

public enum HistoryError: Error {
    case open(String), query(String)
}
