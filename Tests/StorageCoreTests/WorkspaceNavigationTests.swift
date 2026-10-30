import XCTest
@testable import StorageCore

final class WorkspaceNavigationTests: XCTestCase {
    func testHistoryRestoresFiltersExpansionSelectionAndPosition() {
        let project = WorkspaceLocation(folder: "/Users/me/code", selectedPath: "/Users/me/code/one",
            search: "build", searchScope: .folder, category: .development, panel: .folders,
            expandedPaths: ["/", "/Users/me/code"], treePageLimits: ["/Users/me/code": 400],
            treeScrollPath: "/Users/me/code/one", listScrollPath: "/Users/me/code/one/a", listLimit: 400)
        let elsewhere = WorkspaceLocation(folder: "/Applications", search: "app", searchScope: .global, panel: .results)
        var history = WorkspaceHistory()
        history.record(project)
        XCTAssertEqual(history.back(from: elsewhere), project)
        XCTAssertTrue(history.canGoForward)
        XCTAssertEqual(history.forward(from: project), elsewhere)
        XCTAssertTrue(history.canGoBack)
    }
    func testNewBranchClearsForwardHistoryAndBackIsNotParent() {
        var history = WorkspaceHistory()
        let source = WorkspaceLocation(folder: "/Users/me/project")
        let external = WorkspaceLocation(folder: "/Library")
        history.record(source)
        XCTAssertEqual(history.back(from: external)?.folder, source.folder)
        history.record(source)
        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.back(from: WorkspaceLocation(folder: "/tmp")), source)
    }
    func testBreadcrumbsPreserveEveryUnicodeAndLiteralComponent() {
        let crumbs = StorageNavigation.breadcrumbs(path: "/Users/João/a%_/folder with spaces", root: "/", rootTitle: "Mac")
        XCTAssertEqual(crumbs.map(\.name), ["Mac", "Users", "João", "a%_", "folder with spaces"])
        XCTAssertEqual(crumbs.last?.path, "/Users/João/a%_/folder with spaces")
        XCTAssertEqual(StorageNavigation.breadcrumbs(path: "/tmp/a/b", root: "/tmp/a", rootTitle: "Scan").map(\.path), ["/tmp/a", "/tmp/a/b"])
        XCTAssertTrue(StorageNavigation.breadcrumbs(path: "/tmp/ab", root: "/tmp/a", rootTitle: "Scan").isEmpty)
    }
    func testUnknownOrInconsistentParentDoesNotInventPercentage() {
        XCTAssertEqual(StorageNavigation.share(bytes: 40, parentBytes: 100), 0.4)
        XCTAssertEqual(StorageNavigation.share(bytes: 0, parentBytes: 100), 0)
        XCTAssertNil(StorageNavigation.share(bytes: 1, parentBytes: 0))
        XCTAssertNil(StorageNavigation.share(bytes: 101, parentBytes: 100))
        XCTAssertNil(StorageNavigation.share(bytes: -1, parentBytes: 100))
    }
}
