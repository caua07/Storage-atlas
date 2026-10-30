import XCTest
import Foundation
import Darwin
@testable import StorageCore

final class StorageCoreTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AtlasTests-" + UUID().uuidString, isDirectory: true).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        root = ScanEngine.canonicalURL(root)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }
    @discardableResult private func file(_ path: String, bytes: Int = 4096) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 37, count: bytes).write(to: url)
        return url
    }
    private func memory() throws -> StorageIndex { try StorageIndex(path: ":memory:") }

    func testDirectoryAndCategoryTotalsDoNotDoubleCountParents() throws {
        try file("project/Sources/main.swift", bytes: 1000)
        try file("project/docs/guide.pdf", bytes: 2000)
        try file("download.zip", bytes: 3000)
        let index = try memory()
        let scan = try ScanEngine.scan(root: root, index: index)
        XCTAssertEqual(scan.fileCount, 3)
        XCTAssertEqual(scan.logicalBytes, 6000)
        let children = try index.entries(scanID: scan.id, parent: root.path)
        XCTAssertEqual(children.reduce(Int64(0)) { $0 + $1.logicalBytes }, 6000)
        XCTAssertEqual(children.first { $0.name == "project" }?.fileCount, 2)
        let categories = try index.categories(scanID: scan.id, allocated: true)
        XCTAssertEqual(categories.reduce(Int64(0)) { $0 + $1.bytes }, scan.allocatedBytes)
        XCTAssertEqual(categories.reduce(Int64(0)) { $0 + $1.count }, 3)
    }

    func testHardLinksCountAllocationOnceWhilePreservingLogicalSize() throws {
        let original = try file("original.txt", bytes: 16_384)
        try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("linked.txt"))
        let index = try memory()
        let scan = try ScanEngine.scan(root: root, index: index)
        let rows = try index.entries(scanID: scan.id, parent: root.path)
        XCTAssertEqual(scan.fileCount, 2)
        XCTAssertEqual(scan.logicalBytes, 32_768)
        XCTAssertEqual(rows.filter { $0.allocatedBytes > 0 }.count, 1)
        var info = stat(); XCTAssertEqual(lstat(original.path, &info), 0)
        let allocated = try original.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize!
        XCTAssertEqual(scan.allocatedBytes, Int64(allocated))
    }

    func testSparseFileRetainsDistinctLogicalAndAllocatedSizes() throws {
        let url = try file("sparse.bin", bytes: 0)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 100 * 1024 * 1024); try handle.close()
        let index = try memory()
        let scan = try ScanEngine.scan(root: root, index: index)
        XCTAssertEqual(scan.logicalBytes, 100 * 1024 * 1024)
        XCTAssertLessThan(scan.allocatedBytes, scan.logicalBytes)
    }

    func testSymbolicLinkCyclesAreNotFollowed() throws {
        try file("nested/real.swift", bytes: 512)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("nested/loop"), withDestinationURL: root)
        let index = try memory()
        let scan = try ScanEngine.scan(root: root, index: index)
        XCTAssertEqual(scan.fileCount, 1)
        XCTAssertEqual(scan.logicalBytes, 512)
        let links = try index.entries(scanID: scan.id, search: "/loop")
        XCTAssertEqual(links.count, 1)
        XCTAssertTrue(links[0].isSymbolicLink)
        XCTAssertEqual(links[0].allocatedBytes, 0)
    }

    func testRecognitionUsesProjectEvidenceAndCreatesDisjointArtifactRoots() throws {
        try file("rust/Cargo.toml", bytes: 0)
        try file("rust/target/debug/program", bytes: 1024)
        try file("ordinary/target/important.txt", bytes: 100)
        try file("web/node_modules/lib/node_modules/inner/index.js", bytes: 512)
        try file("web/.git/objects/local", bytes: 100)
        let index = try memory()
        let scan = try ScanEngine.scan(root: root, index: index)
        let roots = try index.entries(scanID: scan.id, ruleRoots: true)
        XCTAssertEqual(Set(roots.compactMap(\.ruleID)), ["rust", "node", "git"])
        XCTAssertEqual(roots.filter { $0.ruleID == "node" }.count, 1)
        let candidates = try index.entries(scanID: scan.id, reviewOnly: true)
        XCTAssertEqual(Set(candidates.compactMap(\.ruleID)), ["rust", "node"])
        let ordinary = try index.entries(scanID: scan.id, search: "ordinary/target")
        XCTAssertTrue(ordinary.allSatisfy { $0.ruleID == nil })
    }

    func testApplicationContentsInheritApplicationOwnership() throws {
        try file("Editor.app/Contents/Resources/library.js", bytes: 512)
        let index = try memory()
        let scan = try ScanEngine.scan(root: root, index: index)
        let categories = try index.categories(scanID: scan.id, allocated: false)
        XCTAssertEqual(categories.first?.category, .applications)
        XCTAssertEqual(categories.first?.bytes, 512)
        XCTAssertEqual(try index.entries(scanID: scan.id, reviewOnly: true).count, 0)
    }

    func testLiteralSearchEscapesSQLWildcardsAndQuotes() throws {
        try file("exact%b_c's.txt")
        try file("exactZZbQc.txt")
        let index = try memory()
        let scan = try ScanEngine.scan(root: root, index: index)
        XCTAssertEqual(try index.entries(scanID: scan.id, search: "%b_c'").count, 1)
        XCTAssertEqual(try index.entries(scanID: scan.id, search: "' OR 1=1 --").count, 0)
    }

    func testCancellationPersistsAnExplicitPartialSnapshot() throws {
        for i in 0..<100 { try file("files/\(i).txt", bytes: 20) }
        let index = try memory(); let token = ScanCancellation()
        let scan = try ScanEngine.scan(root: root, index: index, cancellation: token) { _ in token.cancel() }
        XCTAssertEqual(scan.status, "cancelled")
        XCTAssertTrue(scan.isPartial)
        XCTAssertLessThan(scan.fileCount, 100)
        XCTAssertEqual(try index.latest()?.status, "cancelled")
    }

    func testIndexDoesNotScanItsOwnGrowingDatabase() throws {
        try file("real.txt", bytes: 1024)
        let index = try StorageIndex(path: root.appendingPathComponent("AtlasData/index.sqlite").path)
        let scan = try ScanEngine.scan(root: root, index: index)
        XCTAssertEqual(scan.fileCount, 1)
        XCTAssertEqual(scan.logicalBytes, 1024)
        XCTAssertTrue(try index.entries(scanID: scan.id, search: "AtlasData").isEmpty)
    }

    func testUnreadableDirectoriesProduceCoverageGaps() throws {
        let hidden = try file("restricted/secret.txt")
        let directory = hidden.deletingLastPathComponent()
        XCTAssertEqual(chmod(directory.path, 0), 0)
        defer { chmod(directory.path, 0o700) }
        let index = try memory()
        let scan = try ScanEngine.scan(root: root, index: index)
        XCTAssertGreaterThan(scan.issueCount, 0)
        XCTAssertTrue(scan.isPartial)
        XCTAssertFalse(try index.issues(scanID: scan.id).isEmpty)
    }

    func testSnapshotSurvivesReopeningIndex() throws {
        try file("files/readme.md")
        let path = root.appendingPathComponent("AtlasData/index.sqlite").path
        var index: StorageIndex? = try StorageIndex(path: path)
        let scan = try ScanEngine.scan(root: root, index: index!)
        index = nil
        let reopened = try StorageIndex(path: path)
        XCTAssertEqual(try reopened.latest()?.id, scan.id)
        XCTAssertEqual(try reopened.entries(scanID: scan.id, parent: root.path).count, 1)
    }

    func testInvalidScopeIsRejectedBeforeCreatingScan() throws {
        let index = try memory()
        XCTAssertThrowsError(try ScanEngine.scan(root: root.appendingPathComponent("missing"), index: index))
        XCTAssertNil(try index.latest())
    }

    func testSimilarlyNamedToolFoldersAreNotMisidentified() throws {
        try file("Library/Developer/Xcode/DerivedData/real.o")
        try file("Library/Developer/Xcode/DerivedData-backup/personal.txt")
        try file(".cargo/registry-backup/important.txt")
        let index = try memory()
        let scan = try ScanEngine.scan(root: root, index: index)
        let recognized = try index.entries(scanID: scan.id, reviewOnly: true)
        XCTAssertEqual(recognized.count, 1)
        XCTAssertEqual(recognized.first?.ruleID, "xcode")
        XCTAssertTrue(try index.entries(scanID: scan.id, search: "registry-backup").allSatisfy { $0.ruleID == nil })
    }

    func testReopeningAnInterruptedCheckpointPreservesConsistentTotals() throws {
        try file("one.txt", bytes: 1024)
        let path = root.appendingPathComponent("AtlasData/index.sqlite").path
        var index: StorageIndex? = try StorageIndex(path: path)
        let complete = try ScanEngine.scan(root: root, index: index!)
        let entries = try index!.entries(scanID: complete.id, parent: root.path)
        let interrupted = ScanSummary(id: UUID().uuidString, root: root.path, started: Date(), status: "scanning", fileCount: complete.fileCount, logicalBytes: complete.logicalBytes, allocatedBytes: complete.allocatedBytes, issueCount: 0)
        try index!.begin(interrupted)
        try index!.insert(entries, scanID: interrupted.id, checkpoint: interrupted)
        index = nil
        let reopened = try StorageIndex(path: path)
        let latest = try XCTUnwrap(reopened.latest())
        XCTAssertEqual(latest.status, "interrupted")
        XCTAssertEqual(latest.fileCount, 1)
        XCTAssertEqual(latest.logicalBytes, 1024)
        XCTAssertEqual(try reopened.categories(scanID: latest.id, allocated: true).reduce(Int64(0)) { $0 + $1.bytes }, latest.allocatedBytes)
    }

    func testSelectingTheIndexDirectoryIsExplicitlyRejected() throws {
        let directory = root.appendingPathComponent("AtlasData")
        let index = try StorageIndex(path: directory.appendingPathComponent("index.sqlite").path)
        XCTAssertThrowsError(try ScanEngine.scan(root: directory, index: index))
        XCTAssertNil(try index.latest())
    }

    func testSpacePlanAccountsForAllStagesReserveAndHypotheticalRecovery() {
        let short = SpacePlan(installed: 50, download: 20, workspace: 40, reserve: 20, hypotheticalRecovery: 0, available: 100)
        XCTAssertEqual(short.required, 130)
        XCTAssertEqual(short.headroom, -30)
        XCTAssertFalse(short.fits)
        let fits = SpacePlan(installed: 50, download: 20, workspace: 40, reserve: 20, hypotheticalRecovery: 35, available: 100)
        XCTAssertEqual(fits.headroom, 5)
        XCTAssertTrue(fits.fits)
        let invalid = SpacePlan(installed: -.infinity, download: .nan, workspace: -2, reserve: 0, hypotheticalRecovery: .infinity, available: 10)
        XCTAssertEqual(invalid.required, 0)
        XCTAssertEqual(invalid.hypotheticalRecovery, 0)
    }
}
