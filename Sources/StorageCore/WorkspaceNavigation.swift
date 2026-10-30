import Foundation

public enum WorkspacePanel: String, CaseIterable, Sendable { case folders, results, details }
public enum QueryScope: String, CaseIterable, Sendable { case folder, global }

public struct Breadcrumb: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public init(path: String, name: String) { self.path = path; self.name = name }
}

/// Paths are keys from the metadata index, never filesystem traversal instructions.
public enum StorageNavigation {
    public static func contains(_ path: String, in root: String) -> Bool {
        path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }
    public static func breadcrumbs(path: String, root: String, rootTitle: String) -> [Breadcrumb] {
        guard contains(path, in: root) else { return [] }
        var result = [Breadcrumb(path: root, name: rootTitle)]
        guard path != root else { return result }
        let suffix = path.dropFirst(root == "/" ? 1 : root.count + 1)
        var parent = root
        for component in suffix.split(separator: "/") {
            parent = (parent == "/" ? "/" : parent + "/") + component
            result.append(Breadcrumb(path: parent, name: String(component)))
        }
        return result
    }
    public static func share(bytes: Int64, parentBytes: Int64) -> Double? {
        guard bytes >= 0, parentBytes > 0, bytes <= parentBytes else { return nil }
        return Double(bytes) / Double(parentBytes)
    }
}

/// A navigation stop includes the user's working context, rather than just a path.
public struct WorkspaceLocation: Equatable, Sendable {
    public var folder: String
    public var selectedPath: String?
    public var search: String
    public var searchScope: QueryScope
    public var category: StorageCategory?
    public var panel: WorkspacePanel?
    public var expandedPaths: Set<String>
    public var treePageLimits: [String: Int]
    public var treeScrollPath: String?
    public var listScrollPath: String?
    public var listLimit: Int
    public var listOverride: String?
    public init(folder: String, selectedPath: String? = nil, search: String = "", searchScope: QueryScope = .folder,
                category: StorageCategory? = nil, panel: WorkspacePanel? = nil, expandedPaths: Set<String> = [],
                treePageLimits: [String: Int] = [:], treeScrollPath: String? = nil,
                listScrollPath: String? = nil, listLimit: Int = 200, listOverride: String? = nil) {
        self.folder = folder; self.selectedPath = selectedPath; self.search = search; self.searchScope = searchScope
        self.category = category; self.panel = panel; self.expandedPaths = expandedPaths
        self.treePageLimits = treePageLimits; self.treeScrollPath = treeScrollPath
        self.listScrollPath = listScrollPath; self.listLimit = listLimit; self.listOverride = listOverride
    }
}

public struct WorkspaceHistory: Sendable {
    private var past: [WorkspaceLocation] = []
    private var future: [WorkspaceLocation] = []
    public var canGoBack: Bool { !past.isEmpty }
    public var canGoForward: Bool { !future.isEmpty }
    public init() {}
    public mutating func record(_ location: WorkspaceLocation) {
        if past.last != location { past.append(location) }
        if past.count > 100 { past.removeFirst(past.count - 100) }
        future.removeAll()
    }
    public mutating func back(from current: WorkspaceLocation) -> WorkspaceLocation? {
        guard let destination = past.popLast() else { return nil }
        future.append(current); return destination
    }
    public mutating func forward(from current: WorkspaceLocation) -> WorkspaceLocation? {
        guard let destination = future.popLast() else { return nil }
        past.append(current); return destination
    }
    public mutating func reset() { past.removeAll(); future.removeAll() }
}
