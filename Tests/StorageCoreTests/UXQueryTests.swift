import XCTest
import Foundation
import CSQLite
@testable import StorageCore

final class UXQueryTests: XCTestCase {
    private var fixture: URL!
    override func setUpWithError() throws {
        fixture = ScanEngine.canonicalURL(FileManager.default.temporaryDirectory)
            .appendingPathComponent("AtlasUXQueries-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: fixture) }

    private func scan(_ id: String = "scan", root: String = "/root") -> ScanSummary {
        ScanSummary(id: id, root: root, started: Date(), status: "scanning", fileCount: 0,
                    logicalBytes: 0, allocatedBytes: 0, issueCount: 0)
    }
    private func entry(_ path: String, bytes: Int64 = 0, category: StorageCategory = .other,
                       directory: Bool = false, symbolicLink: Bool = false, rule: String? = nil) -> StorageEntry {
        StorageEntry(path: path, parent: URL(fileURLWithPath: path).deletingLastPathComponent().path,
                     name: URL(fileURLWithPath: path).lastPathComponent, isDirectory: directory,
                     isSymbolicLink: symbolicLink, logicalBytes: bytes == 0 ? 1024 : bytes,
                     allocatedBytes: bytes, fileCount: directory || symbolicLink ? 0 : 1,
                     modified: nil, category: category, ruleID: rule, isRuleRoot: false)
    }
    private func sql(_ value: String, at path: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else { throw IndexError(message: "Fixture open failed") }
        defer { sqlite3_close(db) }
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, value, nil, nil, &error)
        let message = error.map { String(cString: $0) } ?? "Fixture SQL failed"
        sqlite3_free(error)
        guard result == SQLITE_OK else { throw IndexError(message: message) }
    }

    func testTreePagesRetainFoldersLinksZeroAllocationAndDeterministicTies() throws {
        let index = try StorageIndex(path: ":memory:")
        let summary = scan(); try index.begin(summary)
        var rows = (0..<215).map { entry("/root/item-\($0)", bytes: Int64($0 % 5)) }
        rows += [entry("/root/folder", bytes: 50, directory: true), entry("/root/empty", directory: true),
                 entry("/root/symbol", symbolicLink: true), entry("/root/hardlink", category: .development)]
        try index.insert(rows + [entry("/root-other/not-a-child", bytes: 999)], scanID: summary.id)
        let ordered = rows.sorted { $0.allocatedBytes == $1.allocatedBytes ? $0.path < $1.path : $0.allocatedBytes > $1.allocatedBytes }
        var collected: [StorageEntry] = [], offset = 0
        while true {
            let page = try index.children(scanID: summary.id, parent: "/root", limit: 37, offset: offset)
            collected += page.entries; offset += page.entries.count
            if !page.hasMore { break }
            XCTAssertEqual(page.entries.count, 37)
            guard offset < 1000 else { return XCTFail("Pagination did not advance") }
        }
        XCTAssertEqual(collected, ordered)
        XCTAssertEqual(Set(collected.map(\.path)).count, rows.count)
        XCTAssertTrue(collected.contains { $0.isDirectory && $0.allocatedBytes == 0 })
        XCTAssertTrue(collected.contains { $0.isSymbolicLink })
        XCTAssertTrue(collected.contains { $0.path == "/root/hardlink" && $0.allocatedBytes == 0 })
        XCTAssertTrue(try index.children(scanID: summary.id, parent: "/root", offset: offset).entries.isEmpty)
    }

    func testCompositionCountsRegularFilesOnceAndPreservesZeroAllocatedHardlinkPaths() throws {
        let index = try StorageIndex(path: ":memory:")
        let summary = scan(); try index.begin(summary)
        try index.insert([
            entry("/root", bytes: 200, directory: true), entry("/root/child", bytes: 170, directory: true),
            entry("/root/child/source.swift", bytes: 70, category: .development),
            entry("/root/child/source-hardlink", category: .development),
            entry("/root/movie.mp4", bytes: 30, category: .media),
            entry("/root/child/model.gguf", bytes: 100, category: .models, rule: "model"),
            entry("/root/symbol", symbolicLink: true), entry("/root-other/file", bytes: 2000)
        ], scanID: summary.id)
        let composition = try index.composition(scanID: summary.id, within: "/root")
        XCTAssertEqual(composition.allocatedBytes, 200)
        XCTAssertEqual(composition.fileCount, 4)
        XCTAssertTrue(composition.isMixed)
        XCTAssertEqual(composition.classificationVersion, 2)
        XCTAssertEqual(composition.totals.first { $0.category == .development }?.count, 2)
        XCTAssertEqual(composition.totals.first { $0.category == .development }?.bytes, 70)
        XCTAssertEqual(composition.totals.first { $0.category == .models }?.bytes, 100)
        XCTAssertEqual(try index.composition(scanID: summary.id, within: "/root/child").allocatedBytes, 170)
        XCTAssertEqual(try index.composition(scanID: summary.id, within: "/").allocatedBytes, 2200)
        XCTAssertTrue(try index.composition(scanID: summary.id, within: "/empty").totals.isEmpty)
    }

    func testScopedCompositionAndMatchesTreatWildcardPathComponentsLiterally() throws {
        let index = try StorageIndex(path: ":memory:")
        let summary = scan(); try index.begin(summary)
        try index.insert([
            entry("/root%_/a/code.swift", bytes: 10, category: .development),
            entry("/root%_/a/zero-code.swift", category: .development),
            entry("/root%_/100%_literal.txt", bytes: 20, category: .documents),
            entry("/rootXX/a/code.swift", bytes: 30, category: .development),
            entry("/root%_-other/code.swift", bytes: 40, category: .development)
        ], scanID: summary.id)
        XCTAssertEqual(try index.composition(scanID: summary.id, within: "/root%_").allocatedBytes, 30)
        XCTAssertEqual(try index.matchingPaths(scanID: summary.id, search: "code", category: .development, within: "/root%_"),
                       ["/root%_/a/code.swift", "/root%_/a/zero-code.swift"])
        XCTAssertEqual(try index.matchingPaths(scanID: summary.id, search: "100%_", within: "/root%_"), ["/root%_/100%_literal.txt"])
        XCTAssertEqual(try index.largestFiles(scanID: summary.id, search: "100%_", within: "/root%_").map(\.path), ["/root%_/100%_literal.txt"])
        XCTAssertEqual(try index.matchingPaths(scanID: summary.id, search: "code", within: "/").count, 4)
    }

    func testNewModelCategoryRespectsEnclosingApplicationAndGitArtifacts() throws {
        for path in ["model.gguf", "movie.mp4", "Example.app/inside.gguf", "repository/.git/objects/checkpoint.ckpt"] {
            let url = fixture.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 37, count: 4096).write(to: url)
        }
        let index = try StorageIndex(path: ":memory:")
        let summary = try ScanEngine.scan(root: fixture, index: index)
        func category(_ relative: String) throws -> StorageCategory? {
            try index.entry(scanID: summary.id, path: fixture.appendingPathComponent(relative).path)?.category
        }
        XCTAssertEqual(try category("model.gguf"), .models)
        XCTAssertEqual(try category("movie.mp4"), .media)
        XCTAssertEqual(try category("Example.app/inside.gguf"), .applications)
        XCTAssertEqual(try category("repository/.git/objects/checkpoint.ckpt"), .development)
        // Use the scanner's canonical indexed root, preserving /private/var keys.
        let composition = try index.composition(scanID: summary.id, within: summary.root)
        XCTAssertEqual(composition.allocatedBytes, summary.allocatedBytes)
        XCTAssertEqual(composition.fileCount, summary.fileCount)
        XCTAssertEqual(composition.classificationVersion, RuleCatalog.classificationVersion)
    }

    func testLegacyTaxonomyRemainsStoredAsMediaWhileNewScansUseVersionTwo() throws {
        let path = fixture.appendingPathComponent("legacy.sqlite").path
        try sql("""
            CREATE TABLE scans(id TEXT PRIMARY KEY,root TEXT NOT NULL,started REAL NOT NULL,finished REAL,status TEXT NOT NULL,files INTEGER NOT NULL DEFAULT 0,logical INTEGER NOT NULL DEFAULT 0,allocated INTEGER NOT NULL DEFAULT 0,issues INTEGER NOT NULL DEFAULT 0,scope_kind TEXT NOT NULL DEFAULT 'folder');
            CREATE TABLE entries(scan TEXT NOT NULL,path TEXT NOT NULL,parent TEXT NOT NULL,name TEXT NOT NULL,kind INTEGER NOT NULL,logical INTEGER NOT NULL,allocated INTEGER NOT NULL,files INTEGER NOT NULL,modified REAL,category TEXT NOT NULL,rule TEXT,rule_root INTEGER NOT NULL,PRIMARY KEY(scan,path));
            INSERT INTO scans VALUES('old','/legacy',1,2,'complete',1,128,64,0,'folder');
            INSERT INTO entries VALUES('old','/legacy/model.gguf','/legacy','model.gguf',0,128,64,1,NULL,'media','model',1);
            PRAGMA user_version=3;
            """, at: path)
        let index = try StorageIndex(path: path)
        XCTAssertEqual(try index.classificationVersion(scanID: "old"), 1)
        XCTAssertEqual(try index.entry(scanID: "old", path: "/legacy/model.gguf")?.category, .media)
        let old = try index.composition(scanID: "old", within: "/legacy")
        XCTAssertEqual(old.classificationVersion, 1)
        XCTAssertEqual(old.totals.first?.category, .media)
        XCTAssertTrue(try index.largestFiles(scanID: "old", category: .models).isEmpty)
        let next = scan("next"); try index.begin(next)
        try index.insert([entry("/root/model.gguf", bytes: 64, category: .models, rule: "model")], scanID: next.id)
        XCTAssertEqual(try index.classificationVersion(scanID: next.id), 2)
        XCTAssertEqual(try index.largestFiles(scanID: next.id, category: .models).count, 1)
        XCTAssertEqual(try index.entry(scanID: "old", path: "/legacy/model.gguf")?.allocatedBytes, 64)
    }

    func testInterruptedCheckpointRetainsBoundedScopedIssuePathsAndFinishDoesNotDuplicate() throws {
        let path = fixture.appendingPathComponent("checkpoint.sqlite").path
        var writer: StorageIndex? = try StorageIndex(path: path)
        var summary = scan(root: "/root%_"); try writer!.begin(summary)
        let notes = (0..<600).map { ScanIssue(path: $0 == 0 ? "/root%_" : $0 < 400 ? "/root%_/denied-\($0)" : "/rootXX/denied-\($0)", message: "Access denied") }
        summary.fileCount = 1; summary.allocatedBytes = 10; summary.logicalBytes = 10; summary.issueCount = notes.count
        try writer!.insert([entry("/root%_/file", bytes: 10)], scanID: summary.id, checkpoint: summary, issues: notes)
        let reader = try StorageIndex(path: path, readOnly: true)
        XCTAssertEqual(try reader.summary(id: summary.id)?.status, "scanning")
        XCTAssertEqual(try reader.summary(id: summary.id)?.issueCount, 600)
        XCTAssertEqual(try reader.issues(scanID: summary.id).count, 500)
        XCTAssertEqual(try reader.issuesWithin(scanID: summary.id, path: "/root%_").count, 400)
        writer = nil
        let reopened = try StorageIndex(path: path)
        XCTAssertEqual(try reopened.summary(id: summary.id)?.status, "interrupted")
        XCTAssertEqual(try reopened.issuesWithin(scanID: summary.id, path: "/root%_").count, 400)
        summary.status = "cancelled"; summary.finished = Date()
        try reopened.finish(summary, issues: notes)
        XCTAssertEqual(try reader.issues(scanID: summary.id).count, 500)
        XCTAssertEqual(try reader.summary(id: summary.id)?.allocatedBytes, 10)
    }

    func testFailedIssueCheckpointRollsBackEntriesSummaryAndPreviousNotesTogether() throws {
        let path = fixture.appendingPathComponent("rollback.sqlite").path
        let index = try StorageIndex(path: path)
        var summary = scan(); try index.begin(summary)
        summary.fileCount = 1; summary.allocatedBytes = 10; summary.logicalBytes = 10; summary.issueCount = 1
        try index.insert([entry("/root/a", bytes: 10)], scanID: summary.id, checkpoint: summary,
                         issues: [ScanIssue(path: "/root/denied", message: "old")])
        try sql("CREATE TRIGGER reject_note BEFORE INSERT ON issues WHEN NEW.message='reject' BEGIN SELECT RAISE(ABORT,'fixture rejection'); END;", at: path)
        var next = summary; next.fileCount = 2; next.allocatedBytes = 30; next.logicalBytes = 30; next.issueCount = 2
        XCTAssertThrowsError(try index.insert([entry("/root/b", bytes: 20)], scanID: summary.id, checkpoint: next,
                                             issues: [ScanIssue(path: "/root/new-denied", message: "reject")]))
        XCTAssertNil(try index.entry(scanID: summary.id, path: "/root/b"))
        XCTAssertEqual(try index.summary(id: summary.id)?.allocatedBytes, 10)
        XCTAssertEqual(try index.summary(id: summary.id)?.fileCount, 1)
        XCTAssertEqual(try index.summary(id: summary.id)?.issueCount, 1)
        XCTAssertEqual(try index.issues(scanID: summary.id).map(\.message), ["old"])
    }
    func testReadOnlyInterruptLeavesSubsequentQueriesUsableAndNeverInterruptsWriter() throws {
        let path = fixture.appendingPathComponent("interrupt.sqlite").path
        let writer = try StorageIndex(path: path)
        let summary = scan(); try writer.begin(summary)
        let reader = try StorageIndex(path: path, readOnly: true)
        reader.interruptReadQueries()
        writer.interruptReadQueries()
        try writer.insert([entry("/root/a", bytes: 10)], scanID: summary.id)
        XCTAssertEqual(try reader.children(scanID: summary.id, parent: "/root").entries.count, 1)
        reader.interruptReadQueries()
        XCTAssertEqual(try reader.composition(scanID: summary.id, within: "/root").allocatedBytes, 10)
        XCTAssertEqual(try reader.summary(id: summary.id)?.status, "scanning")
    }

    func testReadOnlyInterruptCancelsAnActiveSQLiteStatementAndConnectionRecovers() throws {
        let path = fixture.appendingPathComponent("active-interrupt.sqlite").path
        var writer: StorageIndex? = try StorageIndex(path: path)
        let summary = scan(); try writer!.begin(summary)
        writer = nil
        // A fixture view supplies a deliberately long SQLite statement without
        // creating a huge disk dataset or exposing an arbitrary-SQL app API.
        try sql("""
            ALTER TABLE entries RENAME TO retained_entries;
            CREATE VIEW entries AS WITH RECURSIVE numbers(n) AS (
                SELECT 1 UNION ALL SELECT n+1 FROM numbers WHERE n<1000000000
            ) SELECT 'scan' AS scan, 'other' AS category, 1 AS allocated, 1 AS logical, 0 AS kind FROM numbers;
            """, at: path)
        let reader = try StorageIndex(path: path, readOnly: true)
        let started = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
        let outcome = QueryOutcome()
        DispatchQueue.global(qos: .userInitiated).async {
            started.signal()
            do { _ = try reader.categories(scanID: summary.id, allocated: true) }
            catch { outcome.record(error.localizedDescription) }
            finished.signal()
        }
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        var stopped = false
        for _ in 0..<200 {
            reader.interruptReadQueries()
            if finished.wait(timeout: .now() + .milliseconds(10)) == .success { stopped = true; break }
        }
        guard stopped else { return XCTFail("UI cancellation must interrupt active SQLite work rather than wait for its query lock") }
        XCTAssertTrue(outcome.message?.lowercased().contains("interrupt") == true)
        XCTAssertEqual(try reader.classificationVersion(scanID: summary.id), 2, "A cancelled reader must remain usable")
    }

    func testScopedQueriesPreserveCanonicalPrivateVarNamespaceInsteadOfRewritingAliases() throws {
        let index = try StorageIndex(path: ":memory:")
        var summary = scan(); try index.begin(summary)
        let canonical = "/private/var/atlas/folder", alias = "/var/atlas/folder"
        summary.fileCount = 2; summary.logicalBytes = 30; summary.allocatedBytes = 30; summary.issueCount = 2
        try index.insert([entry(canonical + "/file", bytes: 10), entry(alias + "/file", bytes: 20)],
                         scanID: summary.id, checkpoint: summary,
                         issues: [ScanIssue(path: canonical + "/denied", message: "canonical"), ScanIssue(path: alias + "/denied", message: "alias")])
        XCTAssertEqual(try index.composition(scanID: summary.id, within: canonical).allocatedBytes, 10)
        XCTAssertEqual(try index.composition(scanID: summary.id, within: canonical + "/./child/..").allocatedBytes, 10)
        XCTAssertEqual(try index.composition(scanID: summary.id, within: alias).allocatedBytes, 20)
        XCTAssertEqual(try index.matchingPaths(scanID: summary.id, search: "file", within: canonical), [canonical + "/file"])
        XCTAssertEqual(try index.largestFiles(scanID: summary.id, within: canonical).map(\.path), [canonical + "/file"])
        XCTAssertEqual(try index.issuesWithin(scanID: summary.id, path: canonical).map(\.message), ["canonical"])
    }

    private final class QueryOutcome: @unchecked Sendable {
        private let lock = NSLock()
        private var value: String?
        func record(_ message: String) { lock.lock(); defer { lock.unlock() }; value = message }
        var message: String? { lock.lock(); defer { lock.unlock() }; return value }
    }

}
