import XCTest
@testable import StorageCore

final class TreemapHighlightTests: XCTestCase {
    /// Reference behavior from the original map's complete ancestor expansion.
    private func reference(matches: Set<String>, leaves: Set<String>, groups: Set<String>,
                           rollups: [String: Set<String>]) -> TreemapHighlights {
        var ancestors = Set<String>(), unrepresented = Set<String>()
        for path in matches {
            var chain: [String] = [], current = path
            var represented = groups.contains(path)
            while !current.isEmpty {
                chain.append(current)
                if leaves.contains(current) { represented = true }
                if current == "/" { break }
                guard let slash = current.lastIndex(of: "/") else { break }
                current = slash == current.startIndex ? "/" : String(current[..<slash])
            }
            ancestors.formUnion(chain)
            if !represented { unrepresented.formUnion(chain) }
        }
        return TreemapHighlights(leafPaths: leaves.intersection(ancestors),
            rollupIDs: Set(rollups.filter { unrepresented.contains($0.key) }.flatMap { $0.value }))
    }

    func testMatchesOriginalSemanticsAcrossMixedNestedFrontier() throws {
        let leaves: Set<String> = ["/Users/me/App.app", "/Users/me/work/source.swift", "/Users/me/work/cache",
                                   "/Users/me/café/模型.gguf", "/Users/other"]
        let groups: Set<String> = ["/Users", "/Users/me", "/Users/me/work", "/Users/me/café"]
        let rollups: [String: Set<String>] = ["/": ["root-other"], "/Users/me": ["user-index", "user-pixels"],
                                             "/Users/me/work": ["work-other"], "/Users/me/café": ["unicode-other"]]
        let scenarios: [Set<String>] = [
            [], ["/Users/me/work"], ["/Users/me/App.app/Contents/image.png"],
            ["/Users/me/work/source.swift", "/Users/me/work/cache/nested.bin"],
            ["/Users/me/work/hidden/zero", "/Users/me/unknown.bin"],
            ["/Users/me/work-other/file", "/Users/me/café/模型.gguf", "/Users/me/café/未知"],
            ["/", "/Users/me/work", "/Users/me/café"],
            ["/Users/me/App.app/inside", "/Users/other/file", "/Outside/file", "/Users/me/work/missing"]
        ]
        for matches in scenarios {
            XCTAssertEqual(try TreemapHighlightProjection.resolve(matchingPaths: matches, leafPaths: leaves,
                groupPaths: groups, rollupIDsByParent: rollups),
                reference(matches: matches, leaves: leaves, groups: groups, rollups: rollups))
        }
    }

    func testSharedDirectoriesProduceOnlyVisibleHighlightsAndPreserveRootLeaf() throws {
        let matches = Set((0..<20_000).map { "/work/shared/file-\($0).bin" })
        let rollups: [String: Set<String>] = ["/": ["root"], "/work": ["work"]]
        let omitted = try TreemapHighlightProjection.resolve(matchingPaths: matches, leafPaths: ["/work/sibling"],
            groupPaths: ["/work"], rollupIDsByParent: rollups)
        XCTAssertEqual(omitted.leafPaths, [])
        XCTAssertEqual(omitted.rollupIDs, ["root", "work"])
        let contained = try TreemapHighlightProjection.resolve(matchingPaths: matches, leafPaths: ["/work/shared"],
            groupPaths: ["/work"], rollupIDsByParent: rollups)
        XCTAssertEqual(contained.leafPaths, ["/work/shared"])
        XCTAssertEqual(contained.rollupIDs, [])
        let root = try TreemapHighlightProjection.resolve(matchingPaths: matches, leafPaths: ["/"],
            groupPaths: [], rollupIDsByParent: rollups)
        XCTAssertEqual(root.leafPaths, ["/"])
        XCTAssertEqual(root.rollupIDs, [])
    }

    func testCancellationStopsProjectionBeforeProducingHighlights() async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try TreemapHighlightProjection.resolve(matchingPaths: ["/work/file"], leafPaths: ["/work"],
                groupPaths: [], rollupIDsByParent: [:])
        }
        do { _ = try await task.value; XCTFail("Cancelled highlight work must not complete") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
    }
}
