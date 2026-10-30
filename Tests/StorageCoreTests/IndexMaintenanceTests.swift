import XCTest
import Foundation
import CSQLite
@testable import StorageCore

final class IndexMaintenanceTests: XCTestCase {
    private func add(_ id: Int, to index: StorageIndex, status: String = "cancelled", count: Int = 5) throws {
        var scan = ScanSummary(id: "s\(id)", root: "/", started: Date(timeIntervalSince1970: Double(id)),
                               status: "scanning", fileCount: Int64(count), logicalBytes: Int64(count), allocatedBytes: Int64(count), issueCount: 1, scopeKind: .global)
        try index.begin(scan)
        let rows = (0..<count).map { i in
            StorageEntry(path: "/file\(i)", parent: "/", name: "file\(i)", isDirectory: false,
                         isSymbolicLink: false, logicalBytes: 1, allocatedBytes: 1, fileCount: 1,
                         modified: nil, category: .other, ruleID: nil, isRuleRoot: false)
        }
        try index.insert(rows, scanID: scan.id, checkpoint: scan)
        if status != "scanning" {
            scan.status = status; scan.finished = Date()
            try index.finish(scan, issues: [ScanIssue(path: "/excluded", message: "Scope note")])
        }
    }

    func testCompletionDoesNotWaitForRetentionAndMaintenanceIsBoundedAndResumable() throws {
        let index = try StorageIndex(path: ":memory:")
        for i in 0...6 { try add(i, to: index, status: i == 0 ? "complete" : i == 2 ? "scanning" : "cancelled") }
        XCTAssertNotNil(try index.summary(id: "s1"), "finish publishes completion without deleting old snapshots")
        XCTAssertEqual(try index.latestGlobal()?.id, "s0")
        XCTAssertThrowsError(try index.pruneObsoleteSnapshotBatch(limit: 0))

        XCTAssertTrue(try index.pruneObsoleteSnapshotBatch(limit: 2))
        XCTAssertEqual(try index.entries(scanID: "s1").count, 3)
        XCTAssertNotNil(try index.summary(id: "s1"), "Snapshot metadata survives until its entry rows are removed")
        // A new scan may start between maintenance transactions.
        try add(7, to: index, status: "scanning")
        var batches = 0
        while try index.pruneObsoleteSnapshotBatch(limit: 2) {
            batches += 1
            XCTAssertLessThan(batches, 30)
        }
        XCTAssertNil(try index.summary(id: "s1"))
        XCTAssertTrue(try index.issues(scanID: "s1").isEmpty)
        XCTAssertNotNil(try index.summary(id: "s0"), "Completed global baseline is retained")
        XCTAssertNotNil(try index.summary(id: "s2"), "An older active scan cannot be pruned")
        XCTAssertNotNil(try index.summary(id: "s7"))
        XCTAssertEqual(try index.entries(scanID: "s0").count, 5)
        XCTAssertEqual(try index.entries(scanID: "s7").count, 5)
        XCTAssertFalse(try index.pruneObsoleteSnapshotBatch())
    }

    func testFailedMaintenanceRollsBackWithoutUndoingPublishedCompletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AtlasMaintenance-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("test.sqlite").path
        let index = try StorageIndex(path: path)
        for i in 0...4 { try add(i, to: index, status: "complete", count: 1) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TRIGGER reject_retention BEFORE DELETE ON issues BEGIN SELECT RAISE(ABORT,'fixture maintenance failure'); END", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try index.pruneObsoleteSnapshotBatch(limit: 2))
        XCTAssertEqual(try index.summary(id: "s4")?.status, "complete")
        XCTAssertEqual(try index.entries(scanID: "s0").count, 1, "Failed batch rolls back entry deletion")
        XCTAssertNotNil(try index.summary(id: "s0"))
        XCTAssertEqual(try index.issues(scanID: "s0").count, 1)
        XCTAssertEqual(sqlite3_exec(db, "DROP TRIGGER reject_retention", nil, nil, nil), SQLITE_OK)
        while try index.pruneObsoleteSnapshotBatch(limit: 2) {}
        XCTAssertNil(try index.summary(id: "s0"))
        XCTAssertEqual(try index.latestGlobal()?.id, "s4")
    }
}
