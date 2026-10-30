import Foundation
import CSQLite

public enum EntrySort: String, CaseIterable, Sendable {
    case size, name, modified
    public var title: String { switch self { case .size: "Largest first"; case .name: "Name"; case .modified: "Recently modified" } }
}

public struct IndexError: LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public final class StorageIndex: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let isReadOnly: Bool
    private var issueCacheScanID: String?
    private var issueCache: [ScanIssue] = []
    public let location: String
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String, readOnly: Bool = false) throws {
        location = path
        isReadOnly = readOnly
        if !readOnly && path != ":memory:" {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let flags = readOnly ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open local index."
            if let db { sqlite3_close(db) }
            throw IndexError(message: message)
        }
        sqlite3_busy_timeout(db, 5000)
        do {
            if readOnly {
                // UI queries use an independent lock/connection. Opening one must
                // never run migrations or mark the live writer's scan interrupted.
                try execute("PRAGMA query_only=ON")
                return
            }
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=NORMAL")
            try execute("""
                CREATE TABLE IF NOT EXISTS scans (
                id TEXT PRIMARY KEY, root TEXT NOT NULL, started REAL NOT NULL, finished REAL,
                status TEXT NOT NULL, files INTEGER NOT NULL DEFAULT 0, logical INTEGER NOT NULL DEFAULT 0,
                allocated INTEGER NOT NULL DEFAULT 0, issues INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE IF NOT EXISTS entries (
                scan TEXT NOT NULL, path TEXT NOT NULL, parent TEXT NOT NULL, name TEXT NOT NULL,
                kind INTEGER NOT NULL, logical INTEGER NOT NULL, allocated INTEGER NOT NULL,
                files INTEGER NOT NULL, modified REAL, category TEXT NOT NULL, rule TEXT,
                rule_root INTEGER NOT NULL, PRIMARY KEY(scan,path));
                CREATE INDEX IF NOT EXISTS entries_map_children ON entries(scan,parent,allocated DESC);
                DROP INDEX IF EXISTS entries_parent;
                CREATE INDEX IF NOT EXISTS entries_size ON entries(scan,allocated DESC);
                CREATE INDEX IF NOT EXISTS entries_rules ON entries(scan,rule_root,rule);
                CREATE TABLE IF NOT EXISTS issues (scan TEXT NOT NULL, path TEXT NOT NULL, message TEXT NOT NULL);
                UPDATE scans SET status='interrupted' WHERE status='scanning';
                """)
            // Non-destructive v1 -> v2 migration; historical folder snapshots stay folders.
            let columns = try prepare("PRAGMA table_info(scans)")
            var hasScope = false, hasClassificationVersion = false
            while sqlite3_step(columns) == SQLITE_ROW {
                if string(columns, 1) == "scope_kind" { hasScope = true }
                if string(columns, 1) == "classification_version" { hasClassificationVersion = true }
            }
            sqlite3_finalize(columns)
            if !hasScope { try execute("ALTER TABLE scans ADD COLUMN scope_kind TEXT NOT NULL DEFAULT 'folder'") }
            if !hasClassificationVersion { try execute("ALTER TABLE scans ADD COLUMN classification_version INTEGER NOT NULL DEFAULT 1") }
            try execute("CREATE TABLE IF NOT EXISTS scan_roots (scan TEXT NOT NULL, path TEXT NOT NULL, namespace TEXT NOT NULL, device INTEGER NOT NULL, volume TEXT, PRIMARY KEY(scan,path)); PRAGMA user_version=4")
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }

    /// Waits for this connection's statements before releasing it for app replacement.
    public func closeForAppUpdate() {
        lock.lock(); defer { lock.unlock() }
        if let db { sqlite3_close_v2(db); self.db = nil }
    }

    /// SQLite explicitly permits interrupting a connection from another thread.
    /// Do not acquire the query lock: that would wait for the work being cancelled.
    /// Writer connections deliberately ignore this UI cancellation hook.
    public func interruptReadQueries() {
        guard isReadOnly, let db else { return }
        sqlite3_interrupt(db)
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "Local index error."
            sqlite3_free(error)
            throw IndexError(message: message)
        }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
        return statement
    }
    private func bind(_ strings: [String], to statement: OpaquePointer) {
        for (i, value) in strings.enumerated() { sqlite3_bind_text(statement, Int32(i + 1), value, -1, transient) }
    }
    private func step(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
    }
    private func string(_ s: OpaquePointer, _ c: Int32) -> String { sqlite3_column_text(s, c).map { String(cString: $0) } ?? "" }
    /// Called inside a write transaction for checkpoints. Retained rows are bounded,
    /// while ScanSummary.issueCount records the total including omitted notes.
    private func replaceIssues(_ issues: [ScanIssue], scanID: String) throws {
        let retained = Array(issues.prefix(500))
        if issueCacheScanID == scanID, issueCache.count == retained.count,
           zip(issueCache, retained).allSatisfy({ pair in pair.0.path == pair.1.path && pair.0.message == pair.1.message }) { return }
        let deletion = try prepare("DELETE FROM issues WHERE scan=?")
        defer { sqlite3_finalize(deletion) }; bind([scanID], to: deletion); try step(deletion)
        let insertion = try prepare("INSERT INTO issues VALUES(?,?,?)")
        defer { sqlite3_finalize(insertion) }
        for issue in retained {
            sqlite3_reset(insertion); sqlite3_clear_bindings(insertion)
            bind([scanID, issue.path, issue.message], to: insertion); try step(insertion)
        }
    }
    private func rememberIssues(_ issues: [ScanIssue], scanID: String) {
        // Update only after COMMIT: a rolled-back note must never make the next
        // checkpoint skip persistence. Once the retained 500 stop changing this
        // also avoids rewriting them for every 512 files of a multi-million scan.
        issueCacheScanID = scanID; issueCache = Array(issues.prefix(500))
    }

    public func begin(_ summary: ScanSummary) throws {
        lock.lock(); defer { lock.unlock() }
        let s = try prepare("INSERT INTO scans(id,root,started,status,scope_kind,classification_version) VALUES(?,?,?,'scanning',?,?)")
        defer { sqlite3_finalize(s) }
        bind([summary.id, summary.root], to: s)
        sqlite3_bind_double(s, 3, summary.started.timeIntervalSince1970)
        sqlite3_bind_text(s, 4, summary.scopeKind.rawValue, -1, transient)
        sqlite3_bind_int(s, 5, Int32(RuleCatalog.classificationVersion))
        try step(s)
    }
    public func insert(_ entries: [StorageEntry], scanID: String, checkpoint: ScanSummary? = nil, issues: [ScanIssue]? = nil) throws {
        guard !entries.isEmpty || checkpoint != nil || issues != nil else { return }
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do {
            let s = try prepare("INSERT OR REPLACE INTO entries VALUES(?,?,?,?,?,?,?,?,?,?,?,?)")
            defer { sqlite3_finalize(s) }
            for e in entries {
                sqlite3_reset(s); sqlite3_clear_bindings(s)
                bind([scanID, e.path, e.parent, e.name], to: s)
                sqlite3_bind_int(s, 5, e.isSymbolicLink ? 2 : (e.isDirectory ? 1 : 0))
                sqlite3_bind_int64(s, 6, e.logicalBytes); sqlite3_bind_int64(s, 7, e.allocatedBytes)
                sqlite3_bind_int64(s, 8, e.fileCount)
                if let date = e.modified { sqlite3_bind_double(s, 9, date.timeIntervalSince1970) }
                sqlite3_bind_text(s, 10, e.category.rawValue, -1, transient)
                if let rule = e.ruleID { sqlite3_bind_text(s, 11, rule, -1, transient) }
                sqlite3_bind_int(s, 12, e.isRuleRoot ? 1 : 0)
                try step(s)
            }
            if let checkpoint {
                let update = try prepare("UPDATE scans SET files=?,logical=?,allocated=?,issues=? WHERE id=?")
                defer { sqlite3_finalize(update) }
                sqlite3_bind_int64(update, 1, checkpoint.fileCount)
                sqlite3_bind_int64(update, 2, checkpoint.logicalBytes)
                sqlite3_bind_int64(update, 3, checkpoint.allocatedBytes)
                sqlite3_bind_int64(update, 4, Int64(checkpoint.issueCount))
                sqlite3_bind_text(update, 5, scanID, -1, transient)
                try step(update)
            }
            if let issues { try replaceIssues(issues, scanID: scanID) }
            try execute("COMMIT")
            if let issues { rememberIssues(issues, scanID: scanID) }
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func finish(_ summary: ScanSummary, issues: [ScanIssue]) throws {
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do {
            let s = try prepare("UPDATE scans SET finished=?,status=?,files=?,logical=?,allocated=?,issues=? WHERE id=?")
            defer { sqlite3_finalize(s) }
            sqlite3_bind_double(s, 1, (summary.finished ?? Date()).timeIntervalSince1970)
            sqlite3_bind_text(s, 2, summary.status, -1, transient)
            sqlite3_bind_int64(s, 3, summary.fileCount); sqlite3_bind_int64(s, 4, summary.logicalBytes)
            sqlite3_bind_int64(s, 5, summary.allocatedBytes); sqlite3_bind_int64(s, 6, Int64(summary.issueCount))
            sqlite3_bind_text(s, 7, summary.id, -1, transient)
            try step(s)
            try replaceIssues(issues, scanID: summary.id)
            try execute("COMMIT")
            rememberIssues(issues, scanID: summary.id)
        } catch { try? execute("ROLLBACK"); throw error }
    }

    /// Optional maintenance, separate from publishing a completed scan. Each call
    /// removes at most `limit` obsolete entry rows and releases the writer lock.
    /// Only Atlas metadata is affected; scanned files are never touched.
    @discardableResult public func pruneObsoleteSnapshotBatch(limit: Int = 512) throws -> Bool {
        guard (1...4096).contains(limit) else { throw IndexError(message: "Invalid index maintenance batch size.") }
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do {
            // Keep the newest three, the completed global baseline and every active scan.
            let retained = "SELECT id FROM scans ORDER BY started DESC LIMIT 3"
            let completed = "SELECT id FROM scans WHERE scope_kind='global' AND status='complete' ORDER BY started DESC LIMIT 1"
            let keep = "SELECT id FROM (\(retained)) UNION SELECT id FROM (\(completed))"
            let candidate = try prepare("SELECT id FROM scans WHERE status!='scanning' AND id NOT IN (\(keep)) ORDER BY started ASC,id ASC LIMIT 1")
            defer { sqlite3_finalize(candidate) }
            let result = sqlite3_step(candidate)
            if result == SQLITE_DONE { try execute("COMMIT"); return false }
            guard result == SQLITE_ROW else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
            let id = string(candidate, 0)
            // Equality on scan uses the existing primary-key index. Do not scan every
            // retained snapshot with a table-wide NOT IN deletion.
            let deletion = try prepare("DELETE FROM entries WHERE rowid IN (SELECT rowid FROM entries WHERE scan=? LIMIT ?)")
            defer { sqlite3_finalize(deletion) }; bind([id], to: deletion)
            sqlite3_bind_int(deletion, 2, Int32(limit)); try step(deletion)
            let removed = sqlite3_changes(db)
            if removed < limit {
                for table in ["issues", "scan_roots", "scans"] {
                    let key = table == "scans" ? "id" : "scan"
                    let statement = try prepare("DELETE FROM \(table) WHERE \(key)=?")
                    defer { sqlite3_finalize(statement) }; bind([id], to: statement); try step(statement)
                }
            }
            try execute("COMMIT")
            return true
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func latest() throws -> ScanSummary? { try latestSummary(global: false, preferCompleted: false) }
    public func latestGlobal(preferCompleted: Bool = true) throws -> ScanSummary? { try latestSummary(global: true, preferCompleted: preferCompleted) }
    private func latestSummary(global: Bool, preferCompleted: Bool) throws -> ScanSummary? {
        lock.lock(); defer { lock.unlock() }
        let filter = global ? " WHERE scope_kind='global'" : ""
        let order = preferCompleted ? "CASE WHEN status='complete' THEN 0 ELSE 1 END,started DESC" : "started DESC"
        let s = try prepare("SELECT id,root,started,finished,status,files,logical,allocated,issues,scope_kind FROM scans\(filter) ORDER BY \(order) LIMIT 1")
        defer { sqlite3_finalize(s) }
        let result = sqlite3_step(s)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
        return ScanSummary(id: string(s,0), root: string(s,1), started: Date(timeIntervalSince1970: sqlite3_column_double(s,2)), finished: sqlite3_column_type(s,3) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s,3)), status: string(s,4), fileCount: sqlite3_column_int64(s,5), logicalBytes: sqlite3_column_int64(s,6), allocatedBytes: sqlite3_column_int64(s,7), issueCount: Int(sqlite3_column_int64(s,8)), scopeKind: ScanScopeKind(rawValue: string(s,9)) ?? .folder)
    }
    public func summary(id: String) throws -> ScanSummary? {
        lock.lock(); defer { lock.unlock() }
        let s = try prepare("SELECT id,root,started,finished,status,files,logical,allocated,issues,scope_kind FROM scans WHERE id=?")
        defer { sqlite3_finalize(s) }; bind([id], to: s)
        let result = sqlite3_step(s)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
        return ScanSummary(id: string(s,0), root: string(s,1), started: Date(timeIntervalSince1970: sqlite3_column_double(s,2)), finished: sqlite3_column_type(s,3) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s,3)), status: string(s,4), fileCount: sqlite3_column_int64(s,5), logicalBytes: sqlite3_column_int64(s,6), allocatedBytes: sqlite3_column_int64(s,7), issueCount: Int(sqlite3_column_int64(s,8)), scopeKind: ScanScopeKind(rawValue: string(s,9)) ?? .folder)
    }
    public func entries(scanID: String, parent: String? = nil, search: String = "", category: StorageCategory? = nil, sort: EntrySort = .size, allocated: Bool = true, ruleRoots: Bool = false, reviewOnly: Bool = false, developerOnly: Bool = false, limit: Int = 500) throws -> [StorageEntry] {
        lock.lock(); defer { lock.unlock() }
        var sql = "SELECT path,parent,name,kind,logical,allocated,files,modified,category,rule,rule_root FROM entries WHERE scan=?"
        var bindings = [scanID]
        if let parent { sql += " AND parent=?"; bindings.append(parent) }
        if !search.isEmpty {
            sql += " AND path LIKE ? ESCAPE '\\'"
            let literal = search.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
            bindings.append("%" + literal + "%")
        }
        if let category { sql += " AND category=?"; bindings.append(category.rawValue) }
        if ruleRoots || reviewOnly { sql += " AND rule_root=1" }
        if developerOnly { sql += " AND rule_root=1 AND rule NOT IN ('app','cache')" }
        if reviewOnly {
            let ids = RuleCatalog.rules.filter(\.reviewable).map(\.id)
            sql += " AND rule IN (" + ids.map { _ in "?" }.joined(separator: ",") + ")"
            bindings += ids
        }
        let order: String
        switch sort { case .size: order = allocated ? "allocated DESC" : "logical DESC"; case .name: order = "name COLLATE NOCASE"; case .modified: order = "modified DESC" }
        sql += " ORDER BY \(order),path LIMIT \(max(1, min(limit, 1000)))"
        let s = try prepare(sql); defer { sqlite3_finalize(s) }; bind(bindings, to: s)
        var results: [StorageEntry] = []
        while true {
            let result = sqlite3_step(s)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
            results.append(readEntry(s))
        }
        return results
    }

    private static let columns = "path,parent,name,kind,logical,allocated,files,modified,category,rule,rule_root"
    private var entryColumns: String { Self.columns }
    static var mapChildrenSQL: String { "SELECT \(columns) FROM entries INDEXED BY entries_map_children WHERE scan=? AND parent=? AND allocated>0 ORDER BY allocated DESC,path LIMIT ?" }
    static let mapChildrenTotalsSQL = "SELECT COALESCE(SUM(allocated),0),COALESCE(SUM(files),0) FROM entries INDEXED BY entries_map_children WHERE scan=? AND parent=? AND allocated>0"
    private func readEntry(_ s: OpaquePointer) -> StorageEntry {
        let kind = sqlite3_column_int(s,3)
        return StorageEntry(path: string(s,0), parent: string(s,1), name: string(s,2), isDirectory: kind == 1, isSymbolicLink: kind == 2, logicalBytes: sqlite3_column_int64(s,4), allocatedBytes: sqlite3_column_int64(s,5), fileCount: sqlite3_column_int64(s,6), modified: sqlite3_column_type(s,7) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s,7)), category: StorageCategory(rawValue: string(s,8)) ?? .other, ruleID: sqlite3_column_type(s,9) == SQLITE_NULL ? nil : string(s,9), isRuleRoot: sqlite3_column_int(s,10) == 1)
    }
    private func escapedLike(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    }
    private func literalSearch(_ search: String) -> String { "%" + escapedLike(search) + "%" }
    public func recordRoots(_ roots: [GlobalScanRoot], scanID: String) throws {
        lock.lock(); defer { lock.unlock() }
        let s = try prepare("INSERT OR REPLACE INTO scan_roots VALUES(?,?,?,?,?)")
        defer { sqlite3_finalize(s) }
        for root in roots {
            sqlite3_reset(s); sqlite3_clear_bindings(s)
            bind([scanID, root.url.path, root.namespacePath], to: s)
            sqlite3_bind_int64(s, 4, Int64(root.deviceID))
            if let volume = root.volumeID { sqlite3_bind_text(s, 5, volume, -1, transient) }
            try step(s)
        }
    }
    public func entry(scanID: String, path: String) throws -> StorageEntry? {
        lock.lock(); defer { lock.unlock() }
        let s = try prepare("SELECT \(entryColumns) FROM entries WHERE scan=? AND path=?")
        defer { sqlite3_finalize(s) }; bind([scanID, path], to: s)
        let result = sqlite3_step(s)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
        return readEntry(s)
    }
    public func mapChildren(scanID: String, parent: String, limit: Int = 256) throws -> MapChildren {
        lock.lock(); defer { lock.unlock() }
        let count = max(0, limit)
        let s = try prepare(Self.mapChildrenSQL)
        defer { sqlite3_finalize(s) }; bind([scanID, parent], to: s); sqlite3_bind_int64(s, 3, Int64(count))
        var rows: [StorageEntry] = []
        while true {
            let result = sqlite3_step(s)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
            rows.append(readEntry(s))
        }
        let totals = try prepare(Self.mapChildrenTotalsSQL)
        defer { sqlite3_finalize(totals) }; bind([scanID, parent], to: totals)
        guard sqlite3_step(totals) == SQLITE_ROW else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
        return MapChildren(entries: rows, remainderBytes: sqlite3_column_int64(totals, 0) - rows.reduce(0) { $0 + $1.allocatedBytes }, remainderCount: sqlite3_column_int64(totals, 1) - rows.reduce(0) { $0 + $1.fileCount })
    }
    /// Real immediate children; unlike a treemap projection, zero allocation is
    /// retained. At most 1,000 rows are returned per page, plus an existence probe.
    public func children(scanID: String, parent: String, limit: Int = 200, offset: Int = 0) throws -> TreePage {
        lock.lock(); defer { lock.unlock() }
        let count = max(1, min(limit, 1000))
        let s = try prepare("SELECT \(entryColumns) FROM entries INDEXED BY entries_map_children WHERE scan=? AND parent=? ORDER BY allocated DESC,path LIMIT ? OFFSET ?")
        defer { sqlite3_finalize(s) }; bind([scanID, parent], to: s)
        sqlite3_bind_int64(s, 3, Int64(count + 1)); sqlite3_bind_int64(s, 4, Int64(max(0, offset)))
        var rows: [StorageEntry] = []
        while true {
            let result = sqlite3_step(s)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
            rows.append(readEntry(s))
        }
        return TreePage(entries: Array(rows.prefix(count)), hasMore: rows.count > count)
    }

    public func classificationVersion(scanID: String) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        let s = try prepare("SELECT classification_version FROM scans WHERE id=?")
        defer { sqlite3_finalize(s) }; bind([scanID], to: s)
        let result = sqlite3_step(s)
        if result == SQLITE_DONE {
            throw IndexError(message: "The indexed snapshot is no longer available. Refresh storage to rebuild it.")
        }
        guard result == SQLITE_ROW else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
        return Int(sqlite3_column_int(s, 0))
    }

    /// Scope is a literal, case-preserving path boundary. The binary range uses
    /// the scan/path primary key; LIKE also escapes user '%' and '_' components.
    /// Normalize only dot components. Foundation's standardizedFileURL can shorten
    /// /private/var to /var, which would stop matching the scanner's canonical keys.
    private func normalizedScope(_ input: String) -> String {
        let absolute = input.hasPrefix("/") ? input : FileManager.default.currentDirectoryPath + "/" + input
        var components: [Substring] = []
        for component in absolute.split(separator: "/") {
            if component == "." { continue }
            if component == ".." { if !components.isEmpty { components.removeLast() } }
            else { components.append(component) }
        }
        return "/" + components.joined(separator: "/")
    }
    private func descendantFilter(within: String?) -> (sql: String, bindings: [String]) {
        guard let within else { return ("", []) }
        let scope = normalizedScope(within)
        guard scope != "/" else { return ("", []) }
        let prefix = scope + "/"
        return (" AND path>=? AND path<? AND path LIKE ? ESCAPE '\\'", [prefix, scope + "0", escapedLike(prefix) + "%"])
    }

    public func composition(scanID: String, within: String) throws -> ScopeComposition {
        lock.lock(); defer { lock.unlock() }
        let scope = descendantFilter(within: within)
        let s = try prepare("SELECT category,COALESCE(SUM(allocated),0),COUNT(*) FROM entries INDEXED BY sqlite_autoindex_entries_1 WHERE scan=?\(scope.sql) AND kind=0 GROUP BY category ORDER BY 2 DESC,category")
        defer { sqlite3_finalize(s) }; bind([scanID] + scope.bindings, to: s)
        var totals: [CategoryTotal] = []
        while true {
            let result = sqlite3_step(s)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
            totals.append(CategoryTotal(category: StorageCategory(rawValue: string(s, 0)) ?? .other,
                                        bytes: sqlite3_column_int64(s, 1), count: sqlite3_column_int64(s, 2)))
        }
        return ScopeComposition(totals: totals, allocatedBytes: totals.reduce(0) { $0 + $1.bytes },
                                fileCount: totals.reduce(0) { $0 + $1.count }, classificationVersion: try classificationVersion(scanID: scanID))
    }
    public func largestFiles(scanID: String, search: String = "", category: StorageCategory? = nil, within: String? = nil, limit: Int = 256) throws -> [StorageEntry] {
        lock.lock(); defer { lock.unlock() }
        var filter = category == nil ? "" : " AND category=?"
        var bindings = [scanID, literalSearch(search)] + (category.map { [$0.rawValue] } ?? [])
        // Selective literal text can be rejected from the covering scan/path key
        // before row fetches; do not walk allocation order over millions of misses.
        var pathIndex = search.isEmpty ? "" : " INDEXED BY sqlite_autoindex_entries_1"
        let scope = within.map { normalizedScope($0) }
        if let scope, scope != "/" {
            let prefix = scope + "/"
            // Bound the primary-key range before sorting a scoped precision list.
            // This avoids walking the whole-scan size index to find a small subtree.
            pathIndex = " INDEXED BY sqlite_autoindex_entries_1"
            filter += " AND path>=? AND path<? AND path LIKE ? ESCAPE '\\'"
            bindings += [prefix, scope + "0", escapedLike(prefix) + "%"]
        }
        let s = try prepare("SELECT \(entryColumns) FROM entries\(pathIndex) WHERE scan=? AND path LIKE ? ESCAPE '\\'\(filter) AND kind IN (0,2) ORDER BY allocated DESC,path LIMIT ?")
        defer { sqlite3_finalize(s) }; bind(bindings, to: s); sqlite3_bind_int64(s, Int32(bindings.count + 1), Int64(max(1, limit)))
        var rows: [StorageEntry] = []
        while true {
            let result = sqlite3_step(s)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
            rows.append(readEntry(s))
        }
        return rows
    }
    /// All matches, including zero-allocation entries; no explorer-result cap.
    public func matchingPaths(scanID: String, search: String, category: StorageCategory? = nil, within: String? = nil) throws -> Set<String> {
        guard !search.isEmpty || category != nil else { return [] }
        lock.lock(); defer { lock.unlock() }
        let filter = category == nil ? "" : " AND kind=0 AND category=?"
        let scope = descendantFilter(within: within)
        let s = try prepare("SELECT path FROM entries INDEXED BY sqlite_autoindex_entries_1 WHERE scan=? AND path LIKE ? ESCAPE '\\'\(filter)\(scope.sql)")
        defer { sqlite3_finalize(s) }
        bind([scanID, literalSearch(search)] + (category.map { [$0.rawValue] } ?? []) + scope.bindings, to: s)
        var paths = Set<String>()
        while true {
            let result = sqlite3_step(s)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
            paths.insert(string(s,0))
        }
        return paths
    }

    public func categories(scanID: String, allocated: Bool) throws -> [CategoryTotal] {
        lock.lock(); defer { lock.unlock() }
        let s = try prepare("SELECT category,SUM(\(allocated ? "allocated" : "logical")),COUNT(*) FROM entries WHERE scan=? AND kind=0 GROUP BY category ORDER BY 2 DESC")
        defer { sqlite3_finalize(s) }; bind([scanID], to:s)
        var values: [CategoryTotal] = []
        while true {
            let result = sqlite3_step(s)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
            values.append(CategoryTotal(category: StorageCategory(rawValue: string(s,0)) ?? .other, bytes: sqlite3_column_int64(s,1), count: sqlite3_column_int64(s,2)))
        }
        return values
    }
    public func issues(scanID: String) throws -> [ScanIssue] {
        lock.lock(); defer { lock.unlock() }
        let s = try prepare("SELECT path,message FROM issues WHERE scan=? LIMIT 500")
        defer { sqlite3_finalize(s) }; bind([scanID], to:s)
        var values: [ScanIssue] = []
        while true {
            let result = sqlite3_step(s)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
            values.append(ScanIssue(path: string(s,0), message: string(s,1)))
        }
        return values
    }

    public func issuesWithin(scanID: String, path: String) throws -> [ScanIssue] {
        lock.lock(); defer { lock.unlock() }
        let scopePath = normalizedScope(path)
        let scope = descendantFilter(within: scopePath)
        let filter = scope.sql.isEmpty ? "" : " AND (path=? OR (1=1\(scope.sql)))"
        let bindings = [scanID] + (scope.sql.isEmpty ? [] : [scopePath] + scope.bindings)
        let s = try prepare("SELECT path,message FROM issues WHERE scan=?\(filter) ORDER BY path,message LIMIT 500")
        defer { sqlite3_finalize(s) }; bind(bindings, to: s)
        var values: [ScanIssue] = []
        while true {
            let result = sqlite3_step(s)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw IndexError(message: String(cString: sqlite3_errmsg(db))) }
            values.append(ScanIssue(path: string(s,0), message: string(s,1)))
        }
        return values
    }
}
