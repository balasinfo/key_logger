import Foundation
import SQLite3

/// Local-only SQLite persistence for samples. The DB lives under the user's home dir
/// and never leaves the machine unless they explicitly run `export`.
public final class Store {
    private var db: OpaquePointer?
    public let path: URL

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: URL? = nil) throws {
        self.path = path ?? Store.defaultPath
        try FileManager.default.createDirectory(
            at: self.path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard sqlite3_open(self.path.path, &db) == SQLITE_OK else {
            throw StoreError.open(String(cString: sqlite3_errmsg(db)))
        }
        try exec("""
            CREATE TABLE IF NOT EXISTS samples (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts REAL NOT NULL,
                app_name TEXT NOT NULL,
                bundle_id TEXT NOT NULL,
                window_title TEXT,
                url TEXT,
                host TEXT,
                detail TEXT,
                category TEXT NOT NULL,
                quality TEXT NOT NULL
            );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_samples_ts ON samples(ts);")
    }

    deinit { sqlite3_close(db) }

    public static var defaultPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".activitytracker/activity.sqlite")
    }

    public func insert(_ s: ActivitySample) throws {
        let sql = """
            INSERT INTO samples (ts, app_name, bundle_id, window_title, url, host, detail, category, quality)
            VALUES (?,?,?,?,?,?,?,?,?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, s.timestamp.timeIntervalSince1970)
        bindText(stmt, 2, s.appName)
        bindText(stmt, 3, s.bundleID)
        bindText(stmt, 4, s.windowTitle)
        bindText(stmt, 5, s.url)
        bindText(stmt, 6, s.host)
        bindText(stmt, 7, s.detail)
        bindText(stmt, 8, s.category.rawValue)
        bindText(stmt, 9, s.quality.rawValue)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.step(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// All samples with ts >= since, ordered by time.
    public func samples(since: Date) throws -> [ActivitySample] {
        let sql = """
            SELECT ts, app_name, bundle_id, window_title, url, host, detail, category, quality
            FROM samples WHERE ts >= ? ORDER BY ts ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, since.timeIntervalSince1970)

        var out: [ActivitySample] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(ActivitySample(
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)),
                appName: text(stmt, 1) ?? "",
                bundleID: text(stmt, 2) ?? "",
                windowTitle: text(stmt, 3),
                url: text(stmt, 4),
                host: text(stmt, 5),
                detail: text(stmt, 6),
                category: Category(rawValue: text(stmt, 7) ?? "") ?? .unknown,
                quality: Quality(rawValue: text(stmt, 8) ?? "") ?? .neutral
            ))
        }
        return out
    }

    /// Honor a retention window by deleting anything older than `days`.
    @discardableResult
    public func purge(olderThanDays days: Int) throws -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970
        try exec("DELETE FROM samples WHERE ts < \(cutoff);")
        return Int(sqlite3_changes(db))
    }

    // MARK: - Helpers

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let message = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw StoreError.exec(message)
        }
    }

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, idx, value, -1, Store.SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    private func text(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: c)
    }
}

public enum StoreError: Error {
    case open(String), prepare(String), step(String), exec(String)
}
