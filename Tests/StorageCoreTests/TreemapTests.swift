import XCTest
import Foundation
import CoreGraphics
@testable import StorageCore

final class TreemapTests: XCTestCase {
    private func node(_ id: String, _ bytes: Int64, children: [TreemapNode] = []) -> TreemapNode {
        TreemapNode(id: id, name: id, path: "/" + id, bytes: bytes,
                    isDirectory: !children.isEmpty, children: children)
    }
    private func entry(_ path: String, bytes: Int64, directory: Bool = false,
                       count: Int64 = 1, rule: String? = nil) -> StorageEntry {
        StorageEntry(path: path, parent: path == "/" ? "" : (path as NSString).deletingLastPathComponent,
                     name: (path as NSString).lastPathComponent, isDirectory: directory, isSymbolicLink: false,
                     logicalBytes: bytes, allocatedBytes: bytes, fileCount: count, modified: nil,
                     category: .other, ruleID: rule, isRuleRoot: rule != nil)
    }
    private func index(_ entries: [StorageEntry], root: String = "/") throws -> StorageIndex {
        let index = try StorageIndex(path: ":memory:")
        let summary = ScanSummary(id: "test", root: root, started: Date(), status: "scanning",
                                  fileCount: 0, logicalBytes: 0, allocatedBytes: 0, issueCount: 0)
        try index.begin(summary)
        try index.insert(entries, scanID: summary.id)
        return index
    }
    private func descendants(_ nodes: [TreemapNode]) -> [TreemapNode] {
        nodes.flatMap { [$0] + descendants($0.children) }
    }
    private func leaves(_ nodes: [TreemapNode]) -> [TreemapNode] {
        nodes.flatMap { $0.children.isEmpty ? [$0] : leaves($0.children) }
    }
    private func assertPartition(_ result: TreemapResult, bounds: CGRect, bytes: Int64,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let area = Double(bounds.width * bounds.height)
        XCTAssertEqual(result.tiles.reduce(Int64(0)) { $0 + $1.node.bytes }, bytes, file: file, line: line)
        XCTAssertEqual(result.tiles.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) },
                       area, accuracy: max(0.000001, area * 1e-10), file: file, line: line)
        for (i, tile) in result.tiles.enumerated() {
            XCTAssertTrue(tile.rect.width.isFinite && tile.rect.height.isFinite, file: file, line: line)
            XCTAssertGreaterThan(tile.rect.width, 0, file: file, line: line)
            XCTAssertGreaterThan(tile.rect.height, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(tile.rect.minX, bounds.minX - 1e-8, file: file, line: line)
            XCTAssertGreaterThanOrEqual(tile.rect.minY, bounds.minY - 1e-8, file: file, line: line)
            XCTAssertLessThanOrEqual(tile.rect.maxX, bounds.maxX + 1e-8, file: file, line: line)
            XCTAssertLessThanOrEqual(tile.rect.maxY, bounds.maxY + 1e-8, file: file, line: line)
            XCTAssertEqual(Double(tile.rect.width * tile.rect.height) / area,
                           Double(tile.node.bytes) / Double(bytes), accuracy: 1e-9, file: file, line: line)
            for other in result.tiles.dropFirst(i + 1) {
                let overlap = tile.rect.intersection(other.rect)
                XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 1e-8, file: file, line: line)
            }
        }
    }

    func testProportionalSquareRectanglesConserveAreaAtDifferentViewports() {
        let nodes = (1...40).map { node("file-\($0)", Int64($0 * $0)) }
        let total = nodes.reduce(Int64(0)) { $0 + $1.bytes }
        for bounds in [CGRect(x: 23, y: 41, width: 1200, height: 720),
                       CGRect(x: 0, y: 0, width: 360, height: 840),
                       CGRect(x: 0, y: 0, width: 3000, height: 100)] {
            let result = TreemapLayout.layout(nodes: nodes, in: bounds, minimumTileArea: 0)
            assertPartition(result, bounds: bounds, bytes: total)
            XCTAssertEqual(result, TreemapLayout.layout(nodes: nodes.reversed(), in: bounds, minimumTileArea: 0))
        }
        let equal = TreemapLayout.layout(nodes: (0..<16).map { node("\($0)", 100) },
                                         in: CGRect(x: 0, y: 0, width: 400, height: 400))
        XCTAssertTrue(equal.tiles.allSatisfy { abs($0.rect.width - $0.rect.height) < 1e-8 })
    }

    func testHierarchyChildrenReplaceParentWithoutDuplicateAreaAndHitTestingFindsLeaves() {
        let children = [node("project/a", 300), node("project/b", 200)]
        let nodes = [node("project", 500, children: children), node("download", 500)]
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let result = TreemapLayout.layout(nodes: nodes, in: bounds)
        assertPartition(result, bounds: bounds, bytes: 1000)
        XCTAssertEqual(result.groups.map(\.node.id), ["project"])
        XCTAssertFalse(result.tiles.contains { $0.node.id == "project" })
        for tile in result.tiles {
            XCTAssertEqual(result.tile(at: CGPoint(x: tile.rect.midX, y: tile.rect.midY))?.id, tile.id)
        }
        XCTAssertNil(result.tile(at: CGPoint(x: -1, y: -1)))
        let inconsistent = TreemapLayout.layout(nodes: [node("project", 450, children: children)], in: bounds)
        XCTAssertEqual(inconsistent.tiles.map(\.node.id), ["project"])
        XCTAssertTrue(inconsistent.groups.isEmpty)
        assertPartition(inconsistent, bounds: bounds, bytes: 450)
    }

    func testTinySiblingsRollUpExactBytesAndCountsWithoutChangingDenominator() {
        let nodes = [node("large", 999_000)] + (0..<1000).map { node("small/\($0)", 1) }
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let result = TreemapLayout.layout(nodes: nodes, in: bounds, minimumTileArea: 4)
        assertPartition(result, bounds: bounds, bytes: 1_000_000)
        let rollup = result.tiles.first { $0.isRollup }
        XCTAssertEqual(rollup?.node.bytes, 1000)
        XCTAssertEqual(rollup?.node.fileCount, 1000)
        XCTAssertEqual(rollup?.node.path, "/small")
        XCTAssertEqual(result.tiles.count, 2)
        // Search does not enter the layout API: highlighting cannot renormalize area.
        XCTAssertEqual(result, TreemapLayout.layout(nodes: nodes, in: bounds, minimumTileArea: 4))
    }

    func testHighlySkewedWeightsAndZeroAllocationStayHonest() {
        let nodes = [node("huge", 1_000_000_000_000), node("small", 1_000_000), node("zero", 0)]
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let result = TreemapLayout.layout(nodes: nodes, in: bounds, minimumTileArea: 0)
        assertPartition(result, bounds: bounds, bytes: 1_000_001_000_000)
        XCTAssertEqual(result.tiles.count, 2)
        XCTAssertFalse(result.tiles.contains { $0.node.id == "zero" })
        XCTAssertTrue(TreemapLayout.layout(nodes: nodes, in: .zero).tiles.isEmpty)
        XCTAssertTrue(TreemapLayout.layout(nodes: [node("zero", 0)], in: bounds).tiles.isEmpty)
    }

    func testIndexedProjectionBeyondExplorerCapKeepsExactRemainderAndSearchableZeroPaths() throws {
        let files = (0..<1200).map { entry("/file-\($0)", bytes: Int64($0 + 1)) }
        let total = files.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        let index = try index(files + [entry("/", bytes: total, directory: true, count: 1200), entry("/hard-link", bytes: 0)])
        let nodes = try TreemapProjection.load(index: index, scanID: "test", rootPath: "/", childrenLimit: 64)
        XCTAssertEqual(nodes.reduce(Int64(0)) { $0 + $1.bytes }, total)
        XCTAssertEqual(nodes.count, 65)
        let rollup = try XCTUnwrap(nodes.first { $0.isRollup })
        XCTAssertEqual(rollup.bytes, (1...1136).reduce(Int64(0)) { $0 + Int64($1) })
        XCTAssertEqual(rollup.fileCount, 1136)
        XCTAssertEqual(rollup.path, "/")
        XCTAssertEqual(try index.entries(scanID: "test", search: "hard-link").count, 1)
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
        assertPartition(TreemapLayout.layout(nodes: nodes, in: bounds), bounds: bounds, bytes: total)
    }

    func testProjectionBoundedAcrossDeepDirectoriesAndRecognizedPackagesZoomWithoutScan() throws {
        let rows = [entry("/", bytes: 1000, directory: true, count: 2),
                    entry("/Users", bytes: 1000, directory: true, count: 2),
                    entry("/Users/name", bytes: 1000, directory: true, count: 2),
                    entry("/Users/name/project", bytes: 1000, directory: true, count: 2),
                    entry("/Users/name/project/source.swift", bytes: 400),
                    entry("/Users/name/project/node_modules", bytes: 600, directory: true, rule: "node"),
                    entry("/Users/name/project/node_modules/library.js", bytes: 600)]
        let index = try index(rows)
        let nodes = try TreemapProjection.load(index: index, scanID: "test", rootPath: "/", maxDepth: 2)
        XCTAssertTrue(leaves(nodes).contains { $0.name == "source.swift" })
        let package = try XCTUnwrap(leaves(nodes).first { $0.name == "node_modules" })
        XCTAssertTrue(package.children.isEmpty)
        XCTAssertEqual(leaves(nodes).reduce(Int64(0)) { $0 + $1.bytes }, 1000)
        let focused = try TreemapProjection.load(index: index, scanID: "test", rootPath: package.path)
        XCTAssertEqual(focused.first?.name, "library.js")
        XCTAssertEqual(focused.reduce(Int64(0)) { $0 + $1.bytes }, 600)
        let bounded = try TreemapProjection.load(index: index, scanID: "test", rootPath: "/", maxNodes: 4)
        XCTAssertLessThanOrEqual(descendants(bounded).count, 4)
        XCTAssertEqual(leaves(bounded).reduce(Int64(0)) { $0 + $1.bytes }, 1000)
    }

    func testPositiveParentRemainderIsMeasuredAndInconsistentChildrenStayCollapsed() throws {
        let index = try index([entry("/", bytes: 100, directory: true, count: 3),
                               entry("/folder", bytes: 100, directory: true, count: 3),
                               entry("/folder/a", bytes: 60)])
        let nodes = try TreemapProjection.load(index: index, scanID: "test", rootPath: "/")
        XCTAssertEqual(leaves(nodes).reduce(Int64(0)) { $0 + $1.bytes }, 100)
        XCTAssertEqual(leaves(nodes).first { $0.isRollup }?.bytes, 40)
        try index.insert([entry("/folder/a", bytes: 160)], scanID: "test")
        let advancing = try TreemapProjection.load(index: index, scanID: "test", rootPath: "/")
        XCTAssertEqual(leaves(advancing).map(\.path), ["/folder"])
        XCTAssertEqual(leaves(advancing).reduce(Int64(0)) { $0 + $1.bytes }, 100)
    }
}
