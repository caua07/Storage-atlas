import XCTest
import Foundation
@testable import StorageCore

final class UpdateSafetyTests: XCTestCase {
    func testUpdateWaitsForCommitAndRequiresOneExplicitRequest() {
        var gate = UpdateInstallGate()
        gate.downloaded()
        XCTAssertFalse(gate.beginPreparation(scanRunning: false))
        gate.request()
        XCTAssertFalse(gate.beginPreparation(scanRunning: true))
        XCTAssertTrue(gate.beginPreparation(scanRunning: false))
        XCTAssertFalse(gate.beginPreparation(scanRunning: false), "Preparation is one-shot")
        gate.cancel()
        XCTAssertFalse(gate.beginPreparation(scanRunning: false))
    }

    func testSecondWriterIsRejectedUntilOwnerReleasesLock() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AtlasLockTest-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var first: IndexProcessLock? = try IndexProcessLock(directory: directory)
        XCTAssertNotNil(first)
        XCTAssertThrowsError(try IndexProcessLock(directory: directory))
        first = nil
        let second = try IndexProcessLock(directory: directory)
        XCTAssertNotNil(second)
    }

    func testClosingConnectionsPreservesSavedSnapshotAndWAL() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AtlasUpdateClose-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(repeating: 3, count: 8192).write(to: source.appendingPathComponent("fixture.bin"))
        let path = directory.appendingPathComponent("metadata/index.sqlite").path
        let writer = try StorageIndex(path: path)
        let summary = try ScanEngine.scan(root: source, index: writer)
        let reader = try StorageIndex(path: path, readOnly: true)
        reader.interruptReadQueries()
        reader.closeForAppUpdate(); writer.closeForAppUpdate()
        writer.closeForAppUpdate() // Repeated shutdown remains safe.
        let restored = try StorageIndex(path: path)
        XCTAssertEqual(try restored.latest()?.id, summary.id)
        XCTAssertEqual(try restored.latest()?.status, "complete")
        XCTAssertEqual(try restored.latest()?.fileCount, 1)
        XCTAssertEqual(try restored.latest()?.allocatedBytes, summary.allocatedBytes)
    }
}
