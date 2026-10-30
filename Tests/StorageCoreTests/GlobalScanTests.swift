import XCTest
import Foundation
import Darwin
import CSQLite
@testable import StorageCore

final class GlobalScanTests: XCTestCase {
    private var fixture: URL!
    override func setUpWithError() throws {
        fixture = ScanEngine.canonicalURL(FileManager.default.temporaryDirectory).appendingPathComponent("AtlasGlobalTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: fixture) }
    @discardableResult private func file(_ path: String, bytes: Int = 4096) throws -> URL {
        let url = fixture.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 31, count: bytes).write(to: url)
        return url
    }
    private func root(_ relative: String, namespace: String, excluded: [String] = [], mappings: [GlobalPathMapping] = []) throws -> GlobalScanRoot {
        let url = fixture.appendingPathComponent(relative)
        var info = stat(); guard lstat(url.path, &info) == 0 else { throw IndexError(message: "Missing fixture") }
        return GlobalScanRoot(url: url, namespacePath: namespace, deviceID: info.st_dev, excludedPaths: excluded, mappings: mappings)
    }
    private func plan(_ roots: [GlobalScanRoot]) -> GlobalScanPlan { GlobalScanPlan(roots: roots, capacityURL: fixture) }

    func testCompletedTraversalWithScopeNotesRemainsLimitedCoverage() throws {
        try file("source/kept.bin")
        let index = try StorageIndex(path: ":memory:")
        let scope = GlobalScanPlan(roots: [try root("source", namespace: "/")], capacityURL: fixture,
                                   coverageNotes: [ScanIssue(path: "/excluded", message: "Excluded by this scan's scope.")])
        let completed = try ScanEngine.scan(global: scope, index: index)
        XCTAssertTrue(completed.traversalCompleted)
        XCTAssertTrue(completed.isPartial, "Completed traversal must not claim unrestricted disk coverage.")
        XCTAssertEqual(completed.fileCount, 1)
        XCTAssertEqual(completed.issueCount, 1)
        let restored = try XCTUnwrap(index.latestGlobal())
        XCTAssertTrue(restored.traversalCompleted)
        XCTAssertTrue(restored.isPartial)
        XCTAssertEqual(restored.allocatedBytes, completed.allocatedBytes)

        let cancellation = ScanCancellation(); cancellation.cancel()
        let cancelled = try ScanEngine.scan(global: scope, index: index, cancellation: cancellation)
        XCTAssertFalse(cancelled.traversalCompleted)
        XCTAssertTrue(cancelled.isPartial)
        XCTAssertEqual(try index.latestGlobal()?.id, completed.id)
    }

    func testFinalizationProgressPreservesCountsAndPrecedesFinishedSnapshot() throws {
        try file("source/nested/one.bin", bytes: 4096)
        try file("source/two.bin", bytes: 8192)
        let scope = plan([try root("source", namespace: "/")])
        for global in [false, true] {
            let index = try StorageIndex(path: ":memory:")
            let log = ScanPhaseLog()
            let callback: @Sendable (ScanProgress) -> Void = { update in
                log.append(update)
                if update.phase == .savingIndex {
                    let checkpoint = try? index.latest()
                    XCTAssertEqual(checkpoint?.status, "scanning", "Saving is not completion until finish returns.")
                    XCTAssertEqual(checkpoint?.allocatedBytes, update.allocatedBytes)
                    XCTAssertEqual(checkpoint?.fileCount, update.fileCount)
                }
            }
            let summary = try global
                ? ScanEngine.scan(global: scope, index: index, progress: callback)
                : ScanEngine.scan(root: fixture.appendingPathComponent("source"), index: index, progress: callback)
            let updates = log.snapshot()
            let final = updates.filter { $0.phase == .finalizing || $0.phase == .savingIndex }
            XCTAssertEqual(final.map(\.phase), [.finalizing, .savingIndex])
            XCTAssertTrue(final.allSatisfy { $0.fileCount == summary.fileCount && $0.allocatedBytes == summary.allocatedBytes })
            XCTAssertEqual(updates.last?.phase, .savingIndex, "Do not return to Scanning while finishing the index.")
            XCTAssertTrue(summary.traversalCompleted)
            XCTAssertTrue(try XCTUnwrap(index.latest()).traversalCompleted)
        }
    }

    func testStartupTopologyUsesPhysicalAPFSIdentitiesRatherThanPOSIXDeviceSeparation() throws {
        let system: [String: Any] = ["Internal": true, "FilesystemType": "apfs", "APFSVolumeGroupID": "startup-group", "APFSContainerReference": "disk3", "DeviceIdentifier": "disk3s1s1", "VolumeUUID": "system-snapshot"]
        var data = system
        data["DeviceIdentifier"] = "disk3s5"; data["VolumeUUID"] = "data-volume"
        // Physical identities are validated independently of the merged POSIX namespace.
        XCTAssertNoThrow(try GlobalScanPlan.validateStartupTopology(system: system, data: data))
        var invalid = data; invalid["DeviceIdentifier"] = system["DeviceIdentifier"]
        XCTAssertThrowsError(try GlobalScanPlan.validateStartupTopology(system: system, data: invalid))
        invalid = data; invalid["VolumeUUID"] = system["VolumeUUID"]
        XCTAssertThrowsError(try GlobalScanPlan.validateStartupTopology(system: system, data: invalid))
        invalid = data; invalid["APFSVolumeGroupID"] = "unrelated-group"
        XCTAssertThrowsError(try GlobalScanPlan.validateStartupTopology(system: system, data: invalid))
        invalid = data; invalid["Internal"] = false
        XCTAssertThrowsError(try GlobalScanPlan.validateStartupTopology(system: system, data: invalid))
    }

    func testMultipleRootsMergeWithoutParentDuplicationAndShareHardlinkIdentity() throws {
        let original = try file("system/System/core", bytes: 8192)
        try file("data/Users/me/readme", bytes: 1024)
        try FileManager.default.linkItem(at: original, to: fixture.appendingPathComponent("data/Users/me/linked"))
        let index = try StorageIndex(path: ":memory:")
        let roots = [try root("system", namespace: "/"), try root("data", namespace: "/")]
        XCTAssertEqual(roots[0].deviceID, roots[1].deviceID, "The fixture must exercise merged namespaces sharing POSIX st_dev.")
        let summary = try ScanEngine.scan(global: plan(roots), index: index)
        XCTAssertEqual(summary.scopeKind, .global)
        XCTAssertEqual(summary.root, "/")
        XCTAssertEqual(summary.fileCount, 3)
        XCTAssertEqual(summary.logicalBytes, 8192 * 2 + 1024)
        XCTAssertEqual(try index.entry(scanID: summary.id, path: "/")?.allocatedBytes, summary.allocatedBytes)
        let children = try index.mapChildren(scanID: summary.id, parent: "/")
        XCTAssertEqual(Set(children.entries.map(\.path)), ["/System", "/Users"])
        XCTAssertEqual(children.entries.reduce(0) { $0 + $1.allocatedBytes }, summary.allocatedBytes)
        let files = try index.largestFiles(scanID: summary.id)
        XCTAssertEqual(files.filter { $0.allocatedBytes > 0 }.count, 2)
        XCTAssertEqual(try index.categories(scanID: summary.id, allocated: true).reduce(0) { $0 + $1.bytes }, summary.allocatedBytes)
    }

    func testNestedPhysicalRootsAndDuplicateAliasAreTraversedOnce() throws {
        try file("outer/base", bytes: 1024)
        try file("outer/nested/item", bytes: 2048)
        let outer = try root("outer", namespace: "/"), inner = try root("outer/nested", namespace: "/Nested")
        let duplicate = try root("outer/nested", namespace: "/Alias")
        let index = try StorageIndex(path: ":memory:")
        let summary = try ScanEngine.scan(global: plan([outer, inner, duplicate]), index: index)
        XCTAssertEqual(summary.fileCount, 2)
        XCTAssertEqual(summary.logicalBytes, 3072)
        XCTAssertNil(try index.entry(scanID: summary.id, path: "/nested/item"))
        XCTAssertNotNil(try index.entry(scanID: summary.id, path: "/Nested/item"))
        XCTAssertNil(try index.entry(scanID: summary.id, path: "/Alias/item"))
    }

    func testExplicitExclusionsAndFirmlinkProjectionDoNotTraverseAlias() throws {
        try file("system/Users/alias", bytes: 100)
        try file("system/Volumes/external", bytes: 100)
        try file("data/Users/me/actual", bytes: 333)
        try file("data/unmapped/metadata", bytes: 12)
        let system = try root("system", namespace: "/", excluded: [fixture.appendingPathComponent("system/Users").path, fixture.appendingPathComponent("system/Volumes").path])
        let data = try root("data", namespace: "/System/Volumes/Data", mappings: [GlobalPathMapping(relativePath: "Users", namespacePath: "/Users")])
        let index = try StorageIndex(path: ":memory:")
        let summary = try ScanEngine.scan(global: plan([system, data]), index: index)
        XCTAssertEqual(summary.fileCount, 2)
        XCTAssertEqual(summary.logicalBytes, 345)
        XCTAssertNotNil(try index.entry(scanID: summary.id, path: "/Users/me/actual"))
        XCTAssertNotNil(try index.entry(scanID: summary.id, path: "/System/Volumes/Data/unmapped/metadata"))
        XCTAssertTrue(try index.matchingPaths(scanID: summary.id, search: "external").isEmpty)
    }

    func testStaleDeviceBoundaryIsRejectedBeforeSnapshot() throws {
        try file("source/one")
        let verified = try root("source", namespace: "/")
        let stale = GlobalScanRoot(url: verified.url, namespacePath: "/", deviceID: verified.deviceID &+ 1)
        let index = try StorageIndex(path: ":memory:")
        XCTAssertThrowsError(try ScanEngine.scan(global: plan([stale]), index: index))
        XCTAssertNil(try index.latest())
    }

    func testGlobalScanExcludesMetadataByIdentityAndDoesNotFollowSymbolicLinks() throws {
        try file("source/real", bytes: 1024)
        try FileManager.default.createSymbolicLink(at: fixture.appendingPathComponent("source/loop"), withDestinationURL: fixture.appendingPathComponent("source"))
        let index = try StorageIndex(path: fixture.appendingPathComponent("source/Atlas/index.sqlite").path)
        let summary = try ScanEngine.scan(global: plan([try root("source", namespace: "/")]), index: index)
        XCTAssertEqual(summary.fileCount, 1)
        XCTAssertEqual(summary.logicalBytes, 1024)
        XCTAssertTrue(try index.matchingPaths(scanID: summary.id, search: "Atlas").isEmpty)
        XCTAssertEqual(try index.entry(scanID: summary.id, path: "/loop")?.isSymbolicLink, true)
        let links = try index.largestFiles(scanID: summary.id, search: "loop")
        XCTAssertEqual(links.count, 1)
        XCTAssertTrue(links[0].isSymbolicLink)
        XCTAssertEqual(links[0].allocatedBytes, 0)
        XCTAssertEqual(links[0].fileCount, 0)
    }

    func testMapRemainderConservesBytesAndDescendantFileCountsBeyondExplorerCap() throws {
        let index = try StorageIndex(path: ":memory:")
        let summary = ScanSummary(id: "many", root: "/", started: Date(), status: "complete", fileCount: 1202, logicalBytes: 0, allocatedBytes: 0, issueCount: 0, scopeKind: .global)
        try index.begin(summary)
        let rows = (0..<1200).map { i in StorageEntry(path: "/file-\(i)", parent: "/", name: "file-\(i)", isDirectory: false, isSymbolicLink: false, logicalBytes: Int64(i), allocatedBytes: Int64(i + 1), fileCount: 1, modified: nil, category: .other, ruleID: nil, isRuleRoot: false) }
        let directory = StorageEntry(path: "/folder", parent: "/", name: "folder", isDirectory: true, isSymbolicLink: false, logicalBytes: 3, allocatedBytes: 3, fileCount: 2, modified: nil, category: .other, ruleID: nil, isRuleRoot: false)
        let zero = StorageEntry(path: "/zero%_.txt", parent: "/", name: "zero%_.txt", isDirectory: false, isSymbolicLink: false, logicalBytes: 200, allocatedBytes: 0, fileCount: 1, modified: nil, category: .other, ruleID: nil, isRuleRoot: false)
        try index.insert(rows + [directory, zero], scanID: summary.id)
        let map = try index.mapChildren(scanID: summary.id, parent: "/", limit: 10)
        XCTAssertEqual(map.entries.count, 10)
        XCTAssertEqual(map.entries.reduce(0) { $0 + $1.allocatedBytes } + map.remainderBytes, rows.reduce(3) { $0 + $1.allocatedBytes })
        XCTAssertEqual(map.entries.reduce(0) { $0 + $1.fileCount } + map.remainderCount, 1202)
        XCTAssertEqual(try index.mapChildren(scanID: summary.id, parent: "/", limit: 0).remainderCount, 1202)
        XCTAssertEqual(try index.matchingPaths(scanID: summary.id, search: "file-").count, 1200)
        XCTAssertEqual(try index.matchingPaths(scanID: summary.id, search: "%_"), [zero.path])
        XCTAssertEqual(try index.largestFiles(scanID: summary.id, search: "%_").first?.path, zero.path)
    }

    func testMapQueriesSearchCompositeParentIndexInsteadOfWalkingGlobalSizeIndex() throws {
        let path = fixture.appendingPathComponent("query-plan/index.sqlite").path
        let index = try StorageIndex(path: path)
        let summary = ScanSummary(id: "query-plan", root: "/", started: Date(), status: "scanning", fileCount: 1000, logicalBytes: 1000, allocatedBytes: 1000, issueCount: 0)
        try index.begin(summary)
        let rows = (0..<1000).map { i in StorageEntry(path: "/\(i < 995 ? "busy" : "target")/file-\(i)", parent: i < 995 ? "/busy" : "/target", name: "file-\(i)", isDirectory: false, isSymbolicLink: false, logicalBytes: 1, allocatedBytes: Int64(i + 1), fileCount: 1, modified: nil, category: .other, ruleID: nil, isRuleRoot: false) }
        try index.insert(rows, scanID: summary.id)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        for sql in [StorageIndex.mapChildrenSQL, StorageIndex.mapChildrenTotalsSQL] {
            var statement: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(db, "EXPLAIN QUERY PLAN " + sql, -1, &statement, nil), SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            var details: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 3) { details.append(String(cString: text)) }
            }
            XCTAssertTrue(details.contains { $0.contains("SEARCH entries USING INDEX entries_map_children (scan=? AND parent=?") }, details.joined(separator: "; "))
            XCTAssertFalse(details.contains { $0.contains("SCAN entries") || $0.contains("entries_size") }, details.joined(separator: "; "))
        }
        var oldIndex: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='index' AND name='entries_parent'", -1, &oldIndex, nil), SQLITE_OK)
        defer { sqlite3_finalize(oldIndex) }
        XCTAssertEqual(sqlite3_step(oldIndex), SQLITE_DONE, "The superseded parent index should not duplicate the new leading keys.")
        let map = try index.mapChildren(scanID: summary.id, parent: "/target", limit: 2)
        XCTAssertEqual(map.entries.count, 2)
        XCTAssertEqual(map.remainderCount, 3)
        XCTAssertEqual(map.entries.reduce(0) { $0 + $1.allocatedBytes } + map.remainderBytes, rows.suffix(5).reduce(0) { $0 + $1.allocatedBytes })
    }

    func testScopedLargestFilesRespectFolderBoundariesAndLiteralWildcardPaths() throws {
        try file("source/one%_/nested/keep%_.txt", bytes: 1024)
        try file("source/one%_/second.txt", bytes: 2048)
        try file("source/one%_-sibling/keep%_.txt", bytes: 4096)
        try file("source/oneXX/nested/keep%_.txt", bytes: 8192)
        let index = try StorageIndex(path: ":memory:")
        let summary = try ScanEngine.scan(global: plan([try root("source", namespace: "/")]), index: index)
        XCTAssertEqual(Set(try index.largestFiles(scanID: summary.id, within: "/one%_").map(\.path)), ["/one%_/nested/keep%_.txt", "/one%_/second.txt"])
        XCTAssertEqual(try index.largestFiles(scanID: summary.id, search: "keep%_", within: "/one%_").map(\.path), ["/one%_/nested/keep%_.txt"])
        XCTAssertEqual(try index.largestFiles(scanID: summary.id, category: .documents, within: "/one%_", limit: 1).count, 1)
        XCTAssertEqual(try index.largestFiles(scanID: summary.id, within: "/", limit: 100).count, 4)
        XCTAssertEqual(try index.largestFiles(scanID: summary.id, within: "/one%_/..", limit: 2), try index.largestFiles(scanID: summary.id, limit: 2))
        XCTAssertTrue(try index.largestFiles(scanID: summary.id, within: "/missing").isEmpty)
    }

    func testCancelledRefreshesRetainPreviousCompletedGlobalSnapshot() throws {
        try file("source/one")
        let index = try StorageIndex(path: ":memory:"), scope = plan([try root("source", namespace: "/")])
        let complete = try ScanEngine.scan(global: scope, index: index)
        for _ in 0..<4 {
            let cancellation = ScanCancellation(); cancellation.cancel()
            let cancelled = try ScanEngine.scan(global: scope, index: index, cancellation: cancellation)
            XCTAssertEqual(cancelled.status, "cancelled")
        }
        XCTAssertEqual(try index.latestGlobal()?.id, complete.id)
        XCTAssertEqual(try index.latestGlobal(preferCompleted: false)?.status, "cancelled")
        XCTAssertNotNil(try index.entry(scanID: complete.id, path: "/one"))
    }

    func testCategoryMatchesUseFilesRatherThanMixedFolderCategory() throws {
        try file("source/mixed/movie.mp4")
        try file("source/mixed/node_modules/pkg/index.js")
        let index = try StorageIndex(path: ":memory:")
        let summary = try ScanEngine.scan(global: plan([try root("source", namespace: "/")]), index: index)
        XCTAssertEqual(try index.entry(scanID: summary.id, path: "/mixed")?.category, .other)
        XCTAssertTrue(try index.matchingPaths(scanID: summary.id, search: "", category: .other).isEmpty)
        XCTAssertEqual(try index.matchingPaths(scanID: summary.id, search: "", category: .media), ["/mixed/movie.mp4"])
        XCTAssertEqual(try index.matchingPaths(scanID: summary.id, search: "", category: .development), ["/mixed/node_modules/pkg/index.js"])
        XCTAssertTrue(try index.matchingPaths(scanID: summary.id, search: "mixed").contains("/mixed"))
    }

    func testLiveCheckpointHasMatchingRootChildrenAndSummaryBeforeCancellation() throws {
        for i in 0..<600 { try file("source/files/\(i)", bytes: 16) }
        let index = try StorageIndex(path: ":memory:"), token = ScanCancellation()
        let summary = try ScanEngine.scan(global: plan([try root("source", namespace: "/")]), index: index, cancellation: token) { progress in
            guard let id = progress.scanID, let current = try? index.summary(id: id), current.status == "scanning", current.fileCount >= 512,
                  let children = try? index.mapChildren(scanID: id, parent: "/"),
                  let root = try? index.entry(scanID: id, path: "/") else { return }
            XCTAssertEqual(children.entries.reduce(0) { $0 + $1.allocatedBytes } + children.remainderBytes, current.allocatedBytes)
            XCTAssertEqual(root.allocatedBytes, current.allocatedBytes)
            token.cancel()
        }
        XCTAssertTrue(token.isCancelled)
        XCTAssertEqual(summary.status, "cancelled")
    }

    func testLegacySchemaMigratesFolderSnapshotAndInterruptedGlobalSurvivesReopen() throws {
        let path = fixture.appendingPathComponent("index/index.sqlite").path
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE scans(id TEXT PRIMARY KEY,root TEXT NOT NULL,started REAL NOT NULL,finished REAL,status TEXT NOT NULL,files INTEGER NOT NULL DEFAULT 0,logical INTEGER NOT NULL DEFAULT 0,allocated INTEGER NOT NULL DEFAULT 0,issues INTEGER NOT NULL DEFAULT 0); INSERT INTO scans(id,root,started,status) VALUES('legacy','/old',1,'complete');", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        var index: StorageIndex? = try StorageIndex(path: path)
        XCTAssertEqual(try index!.latest()?.scopeKind, .folder)
        XCTAssertNil(try index!.latestGlobal())
        let partial = ScanSummary(id: "partial", root: "/", started: Date(), status: "scanning", fileCount: 1, logicalBytes: 17, allocatedBytes: 9, issueCount: 0, scopeKind: .global)
        try index!.begin(partial)
        let file = StorageEntry(path: "/item", parent: "/", name: "item", isDirectory: false, isSymbolicLink: false, logicalBytes: 17, allocatedBytes: 9, fileCount: 1, modified: nil, category: .other, ruleID: nil, isRuleRoot: false)
        try index!.insert([file], scanID: partial.id, checkpoint: partial)
        index = nil
        let reopened = try StorageIndex(path: path)
        XCTAssertEqual(try reopened.latestGlobal()?.status, "interrupted")
        XCTAssertEqual(try reopened.latestGlobal()?.allocatedBytes, 9)
        XCTAssertEqual(try reopened.mapChildren(scanID: partial.id, parent: "/").entries.first?.allocatedBytes, 9)
        XCTAssertEqual(try reopened.summary(id: "legacy")?.scopeKind, .folder)
    }

    func testReadOnlyConnectionPreservesActiveWriterAndRejectsMutations() throws {
        let path = fixture.appendingPathComponent("reader/index.sqlite").path
        let writer = try StorageIndex(path: path)
        var active = ScanSummary(id: "active", root: "/", started: Date(), status: "scanning", fileCount: 1, logicalBytes: 20, allocatedBytes: 10, issueCount: 0, scopeKind: .global)
        try writer.begin(active)
        let first = StorageEntry(path: "/first", parent: "/", name: "first", isDirectory: false, isSymbolicLink: false, logicalBytes: 20, allocatedBytes: 10, fileCount: 1, modified: nil, category: .other, ruleID: nil, isRuleRoot: false)
        try writer.insert([first], scanID: active.id, checkpoint: active)
        let reader = try StorageIndex(path: path, readOnly: true)
        XCTAssertEqual(try reader.latestGlobal()?.status, "scanning")
        XCTAssertEqual(try writer.summary(id: active.id)?.status, "scanning")
        XCTAssertEqual(try reader.entry(scanID: active.id, path: first.path), first)
        XCTAssertThrowsError(try reader.insert([first], scanID: active.id, checkpoint: active))
        let forbidden = ScanSummary(id: "reader-write", root: "/", started: Date(), status: "scanning", fileCount: 0, logicalBytes: 0, allocatedBytes: 0, issueCount: 0)
        XCTAssertThrowsError(try reader.begin(forbidden))
        XCTAssertNil(try writer.summary(id: forbidden.id))

        let second = StorageEntry(path: "/second", parent: "/", name: "second", isDirectory: false, isSymbolicLink: false, logicalBytes: 30, allocatedBytes: 15, fileCount: 1, modified: nil, category: .other, ruleID: nil, isRuleRoot: false)
        active.fileCount = 2; active.logicalBytes = 50; active.allocatedBytes = 25
        try writer.insert([second], scanID: active.id, checkpoint: active)
        XCTAssertEqual(try reader.summary(id: active.id)?.allocatedBytes, 25)
        XCTAssertEqual(try reader.mapChildren(scanID: active.id, parent: "/").entries.count, 2)

        let missing = fixture.appendingPathComponent("absent/index.sqlite")
        XCTAssertThrowsError(try StorageIndex(path: missing.path, readOnly: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.deletingLastPathComponent().path))
    }
}

private final class ScanPhaseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [ScanProgress] = []
    func append(_ progress: ScanProgress) { lock.lock(); defer { lock.unlock() }; updates.append(progress) }
    func snapshot() -> [ScanProgress] { lock.lock(); defer { lock.unlock() }; return updates }
}
