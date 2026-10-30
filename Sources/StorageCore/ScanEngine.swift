import Foundation
import Darwin

public enum ScanEngine {
    /// Foundation can shorten /private/var to /var, while enumeration returns /private/var.
    /// POSIX canonicalization keeps root, parent keys, and metadata exclusions consistent.
    public static func canonicalURL(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }
    private struct Directory {
        let url: URL
        let rule: RecognitionRule?
        let isRuleRoot: Bool
        let modified: Date?
        var logical: Int64 = 0
        var allocated: Int64 = 0
        var files: Int64 = 0
    }

    public static func scan(root input: URL, index: StorageIndex, cancellation: ScanCancellation = .init(), progress: @Sendable (ScanProgress) -> Void = { _ in }) throws -> ScanSummary {
        let root = canonicalURL(input)
        let ownDirectory = index.location == ":memory:" ? nil : canonicalURL(URL(fileURLWithPath: index.location).deletingLastPathComponent()).path
        if let ownDirectory, root.path == ownDirectory || root.path.hasPrefix(ownDirectory + "/") {
            throw IndexError(message: "Atlas’s own metadata directory is excluded from scans. Choose another folder.")
        }
        var rootStat = stat()
        guard lstat(root.path, &rootStat) == 0, rootStat.st_mode & S_IFMT == S_IFDIR else { throw IndexError(message: "Choose an existing, readable folder to scan.") }
        var summary = ScanSummary(id: UUID().uuidString, root: root.path, started: Date(), status: "scanning", fileCount: 0, logicalBytes: 0, allocatedBytes: 0, issueCount: 0)
        try index.begin(summary)
        let rootRule = RuleCatalog.recognizeDirectory(root, inherited: nil)
        var directories: [String: Directory] = [root.path: Directory(url: root, rule: rootRule, isRuleRoot: rootRule != nil, modified: nil)]
        var issues: [ScanIssue] = []
        var issueCount = 0
        func issue(_ url: URL, _ message: String) {
            issueCount += 1
            if issues.count < 500 { issues.append(ScanIssue(path: url.path, message: message)) }
        }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { url, error in issue(url, error.localizedDescription); return !cancellation.isCancelled }) else {
            throw IndexError(message: "Could not enumerate this folder. Check its permissions or select a different location.")
        }
        var batch: [StorageEntry] = []
        var hardLinks: Set<String> = []
        var lastProgress = Date.distantPast
        while let url = enumerator.nextObject() as? URL {
            if cancellation.isCancelled { break }
            if let ownDirectory, url.path == ownDirectory || url.path.hasPrefix(ownDirectory + "/") {
                enumerator.skipDescendants(); continue
            }
            var info = stat()
            guard lstat(url.path, &info) == 0 else { issue(url, String(cString: strerror(errno))); continue }
            if info.st_dev != rootStat.st_dev { enumerator.skipDescendants(); issue(url, "Another mounted volume was excluded from this scan."); continue }
            let parent = url.deletingLastPathComponent().path
            let inherited = directories[parent]?.rule
            let kind = info.st_mode & S_IFMT
            if kind == S_IFLNK {
                batch.append(StorageEntry(path: url.path, parent: parent, name: url.lastPathComponent, isDirectory: false, isSymbolicLink: true, logicalBytes: 0, allocatedBytes: 0, fileCount: 0, modified: nil, category: .other, ruleID: nil, isRuleRoot: false))
            } else if kind == S_IFDIR {
                let rule = RuleCatalog.recognizeDirectory(url, inherited: inherited)
                directories[url.path] = Directory(url: url, rule: rule, isRuleRoot: rule != nil && inherited == nil, modified: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)))
            } else if kind == S_IFREG {
                let values = try? url.resourceValues(forKeys: keys)
                let logical = max(0, Int64(info.st_size))
                var allocated = max(0, Int64(values?.totalFileAllocatedSize ?? Int(info.st_blocks) * 512))
                if info.st_nlink > 1 {
                    let identity = "\(info.st_dev):\(info.st_ino)"
                    if !hardLinks.insert(identity).inserted { allocated = 0 }
                }
                let rule = inherited ?? (["gguf", "safetensors", "onnx", "ckpt"].contains(url.pathExtension.lowercased()) ? RuleCatalog.rule("model") : nil)
                batch.append(StorageEntry(path: url.path, parent: parent, name: url.lastPathComponent, isDirectory: false, isSymbolicLink: false, logicalBytes: logical, allocatedBytes: allocated, fileCount: 1, modified: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)), category: RuleCatalog.category(for: url, inherited: rule), ruleID: rule?.id, isRuleRoot: inherited == nil && rule != nil))
                directories[parent]?.logical += logical
                directories[parent]?.allocated += allocated
                directories[parent]?.files += 1
                summary.fileCount += 1; summary.logicalBytes += logical; summary.allocatedBytes += allocated
            }
            if batch.count >= 512 {
                summary.issueCount = issueCount
                try index.insert(batch, scanID: summary.id, checkpoint: summary, issues: issues); batch.removeAll(keepingCapacity: true)
            }
            if Date().timeIntervalSince(lastProgress) > 0.15 {
                progress(ScanProgress(fileCount: summary.fileCount, allocatedBytes: summary.allocatedBytes, currentPath: url.path, issueCount: issueCount))
                lastProgress = Date()
            }
        }
        summary.issueCount = issueCount
        // Children first: every directory contributes once to its immediate parent.
        progress(ScanProgress(fileCount: summary.fileCount, allocatedBytes: summary.allocatedBytes, currentPath: root.path, issueCount: issueCount, phase: .finalizing))
        for path in directories.keys.sorted(by: { $0.count > $1.count }) {
            guard let d = directories[path] else { continue }
            let parent = d.url.deletingLastPathComponent().path
            batch.append(StorageEntry(path: path, parent: path == root.path ? "" : parent, name: d.url.lastPathComponent, isDirectory: true, isSymbolicLink: false, logicalBytes: d.logical, allocatedBytes: d.allocated, fileCount: d.files, modified: d.modified, category: d.rule?.category ?? .other, ruleID: d.rule?.id, isRuleRoot: d.isRuleRoot))
            if path != root.path {
                directories[parent]?.logical += d.logical
                directories[parent]?.allocated += d.allocated
                directories[parent]?.files += d.files
            }
            if batch.count >= 512 { try index.insert(batch, scanID: summary.id, checkpoint: summary, issues: issues); batch.removeAll(keepingCapacity: true) }
        }
        try index.insert(batch, scanID: summary.id, checkpoint: summary, issues: issues)
        summary.finished = Date(); summary.status = cancellation.isCancelled ? "cancelled" : "complete"; summary.issueCount = issueCount
        progress(ScanProgress(fileCount: summary.fileCount, allocatedBytes: summary.allocatedBytes, currentPath: root.path, issueCount: issueCount, phase: .savingIndex))
        try index.finish(summary, issues: issues)
        return summary
    }
    /// Enumerates the verified physical namespaces as one session with shared identity accounting.
    public static func scan(global plan: GlobalScanPlan, index: StorageIndex, cancellation: ScanCancellation = .init(), progress: @Sendable (ScanProgress) -> Void = { _ in }) throws -> ScanSummary {
        guard !plan.roots.isEmpty else { throw IndexError(message: "The global scan plan has no verified roots.") }
        // Validate every root before creating a snapshot; discovery may have become stale.
        for root in plan.roots {
            var info = stat()
            guard lstat(root.url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_dev == root.deviceID else {
                throw IndexError(message: "A planned startup mount changed or became unavailable. Refresh the volume plan.")
            }
        }
        var summary = ScanSummary(id: UUID().uuidString, root: "/", started: Date(), status: "scanning", fileCount: 0, logicalBytes: 0, allocatedBytes: 0, issueCount: 0, scopeKind: .global)
        try index.begin(summary)
        try index.recordRoots(plan.roots, scanID: summary.id)
        var directories: [String: Directory] = [:]
        var dirty = Set<String>()
        var batch: [StorageEntry] = []
        var hardLinks = Set<String>(), seenDirectories = Set<String>()
        var issues = Array(plan.coverageNotes.prefix(500)), issueCount = plan.coverageNotes.count
        var ownIdentity: String?
        if index.location != ":memory:" {
            var info = stat()
            let directory = canonicalURL(URL(fileURLWithPath: index.location).deletingLastPathComponent())
            if lstat(directory.path, &info) == 0 { ownIdentity = "\(info.st_dev):\(info.st_ino)" }
        }
        func issue(_ path: String, _ message: String) {
            issueCount += 1
            if issues.count < 500 { issues.append(ScanIssue(path: path, message: message)) }
        }
        func ensureDirectory(_ path: String, rule: RecognitionRule? = nil, modified: Date? = nil) {
            if directories[path] == nil {
                let parent = path == "/" ? "" : URL(fileURLWithPath: path).deletingLastPathComponent().path
                if !parent.isEmpty { ensureDirectory(parent) }
                directories[path] = Directory(url: URL(fileURLWithPath: path), rule: rule, isRuleRoot: rule != nil && directories[parent]?.rule == nil, modified: modified)
                dirty.insert(path)
            } else if let rule, directories[path]?.rule == nil {
                directories[path] = Directory(url: URL(fileURLWithPath: path), rule: rule, isRuleRoot: true, modified: modified, logical: directories[path]!.logical, allocated: directories[path]!.allocated, files: directories[path]!.files)
                dirty.insert(path)
            }
        }
        func entry(_ path: String) -> StorageEntry {
            let d = directories[path]!
            return StorageEntry(path: path, parent: path == "/" ? "" : d.url.deletingLastPathComponent().path, name: path == "/" ? "Mac" : d.url.lastPathComponent, isDirectory: true, isSymbolicLink: false, logicalBytes: d.logical, allocatedBytes: d.allocated, fileCount: d.files, modified: d.modified, category: d.rule?.category ?? .other, ruleID: d.rule?.id, isRuleRoot: d.isRuleRoot)
        }
        func checkpoint() throws {
            summary.issueCount = issueCount
            let rows = batch + dirty.sorted().map(entry)
            try index.insert(rows, scanID: summary.id, checkpoint: summary, issues: issues)
            batch.removeAll(keepingCapacity: true); dirty.removeAll(keepingCapacity: true)
        }
        ensureDirectory("/")
        try checkpoint()
        progress(ScanProgress(fileCount: 0, allocatedBytes: 0, currentPath: "/", issueCount: issueCount, scanID: summary.id))
        var lastCheckpoint = Date(), lastProgress = Date.distantPast
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey]
        for root in plan.roots {
            if cancellation.isCancelled { break }
            var rootInfo = stat(); _ = lstat(root.url.path, &rootInfo)
            let rootIdentity = "\(rootInfo.st_dev):\(rootInfo.st_ino)"
            if rootIdentity == ownIdentity { issue(root.projectedPath(for: root.url.path), "Atlas’s own metadata is excluded."); continue }
            if !seenDirectories.insert(rootIdentity).inserted { continue }
            let rootPath = root.projectedPath(for: root.url.path)
            ensureDirectory(rootPath)
            // An enclosing root must not suppress this constituent's own traversal.
            let prefix = root.url.path == "/" ? "/" : root.url.path + "/"
            let otherRoots = plan.roots.filter { $0.url.path != root.url.path && $0.url.path.hasPrefix(prefix) }.map { $0.url.path }
            guard let enumerator = FileManager.default.enumerator(at: root.url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { url, error in
                issue(root.projectedPath(for: url.path), error.localizedDescription); return !cancellation.isCancelled
            }) else { issue(rootPath, "Could not enumerate this startup namespace."); continue }
            while let physical = enumerator.nextObject() as? URL {
                if cancellation.isCancelled { break }
                let path = root.projectedPath(for: physical.path)
                if (root.excludedPaths + otherRoots).contains(where: { physical.path == $0 || physical.path.hasPrefix($0 + "/") }) {
                    enumerator.skipDescendants(); continue
                }
                var info = stat()
                guard lstat(physical.path, &info) == 0 else { issue(path, String(cString: strerror(errno))); continue }
                if info.st_dev != root.deviceID { enumerator.skipDescendants(); issue(path, "A mount outside the planned startup namespace was excluded."); continue }
                let kind = info.st_mode & S_IFMT
                let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
                ensureDirectory(parent)
                let inherited = directories[parent]?.rule
                if kind == S_IFDIR {
                    let identity = "\(info.st_dev):\(info.st_ino)"
                    if identity == ownIdentity { enumerator.skipDescendants(); continue }
                    if !seenDirectories.insert(identity).inserted { enumerator.skipDescendants(); continue }
                    let rule = RuleCatalog.recognizeDirectory(URL(fileURLWithPath: path), inherited: inherited)
                    ensureDirectory(path, rule: rule, modified: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)))
                } else if kind == S_IFLNK {
                    enumerator.skipDescendants()
                    batch.append(StorageEntry(path: path, parent: parent, name: physical.lastPathComponent, isDirectory: false, isSymbolicLink: true, logicalBytes: 0, allocatedBytes: 0, fileCount: 0, modified: nil, category: .other, ruleID: nil, isRuleRoot: false))
                } else if kind == S_IFREG {
                    let logical = max(0, Int64(info.st_size))
                    let values = try? physical.resourceValues(forKeys: keys)
                    var allocated = max(0, Int64(values?.totalFileAllocatedSize ?? Int(info.st_blocks) * 512))
                    if info.st_nlink > 1, !hardLinks.insert("\(info.st_dev):\(info.st_ino)").inserted { allocated = 0 }
                    let url = URL(fileURLWithPath: path)
                    let rule = inherited ?? (["gguf", "safetensors", "onnx", "ckpt"].contains(url.pathExtension.lowercased()) ? RuleCatalog.rule("model") : nil)
                    batch.append(StorageEntry(path: path, parent: parent, name: physical.lastPathComponent, isDirectory: false, isSymbolicLink: false, logicalBytes: logical, allocatedBytes: allocated, fileCount: 1, modified: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)), category: RuleCatalog.category(for: url, inherited: rule), ruleID: rule?.id, isRuleRoot: inherited == nil && rule != nil))
                    var ancestor = parent
                    while true {
                        directories[ancestor]?.logical += logical; directories[ancestor]?.allocated += allocated; directories[ancestor]?.files += 1
                        dirty.insert(ancestor)
                        if ancestor == "/" { break }
                        ancestor = URL(fileURLWithPath: ancestor).deletingLastPathComponent().path
                    }
                    summary.fileCount += 1; summary.logicalBytes += logical; summary.allocatedBytes += allocated
                }
                let now = Date()
                if batch.count >= 512 || now.timeIntervalSince(lastCheckpoint) >= 2 {
                    try checkpoint(); lastCheckpoint = now
                    progress(ScanProgress(fileCount: summary.fileCount, allocatedBytes: summary.allocatedBytes, currentPath: path, issueCount: issueCount, scanID: summary.id)); lastProgress = now
                }
                if now.timeIntervalSince(lastProgress) >= 0.2 {
                    progress(ScanProgress(fileCount: summary.fileCount, allocatedBytes: summary.allocatedBytes, currentPath: path, issueCount: issueCount, scanID: summary.id)); lastProgress = now
                }
            }
        }
        progress(ScanProgress(fileCount: summary.fileCount, allocatedBytes: summary.allocatedBytes, currentPath: "/", issueCount: issueCount, scanID: summary.id, phase: .finalizing))
        try checkpoint()
        summary.finished = Date(); summary.status = cancellation.isCancelled ? "cancelled" : "complete"; summary.issueCount = issueCount
        progress(ScanProgress(fileCount: summary.fileCount, allocatedBytes: summary.allocatedBytes, currentPath: "/", issueCount: issueCount, scanID: summary.id, phase: .savingIndex))
        try index.finish(summary, issues: issues)
        return summary
    }

}
