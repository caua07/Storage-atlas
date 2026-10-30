import SwiftUI
import AppKit
import Darwin
import StorageCore

@MainActor final class AppModel: ObservableObject {
    @Published var summary: ScanSummary?
    @Published var capacity: VolumeCapacity?
    @Published var issues: [ScanIssue] = []
    @Published var mapNodes: [TreemapNode] = []
    @Published var listEntries: [StorageEntry] = []
    @Published var listLimit = 200
    @Published var listHasMore = false
    @Published var matchingPaths: Set<String> = []
    @Published var selected: StorageEntry?
    @Published var hoveredNode: TreemapNode?
    @Published var hoveredPath: String?
    @Published var panel: WorkspacePanel? {
        didSet { if panel == .folders && oldValue != .folders { prepareTree(revealFocus: !restoringLocation) } }
    }
    @Published var showCoverage = false
    @Published private(set) var readAccess: ReadAccessObservation?
    @Published private(set) var isCheckingReadAccess = false
    @Published private(set) var readAccessNoticeDismissed = false
    private let readAccessPreferences: ReadAccessPreferences
    @Published var isScanning = false
    @Published private(set) var isPreparingForUpdate = false
    let isFixture: Bool
    private var processLock: IndexProcessLock?
    @Published var isCancelling = false
    @Published var isQuerying = false
    @Published var isLoadingComposition = false
    @Published var composition: ScopeComposition?
    @Published var selectedComposition: ScopeComposition?
    @Published var progress: ScanProgress?
    @Published var error: String?
    @Published var currentFolder: String?
    @Published var displayedFolder: String?
    @Published var loadingFolder: String?
    @Published var search = ""
    @Published var searchScope: QueryScope = .folder
    @Published var searchFocusRequest = 0
    @Published var category: StorageCategory?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var listScrollPath: String?
    @Published var treeRoot: StorageEntry?
    @Published var treeChildren: [String: [StorageEntry]] = [:]
    @Published var treeExpanded: Set<String> = []
    @Published var treeLoading: Set<String> = []
    @Published var treeHasMore: Set<String> = []
    @Published var treeSelectedPath: String?
    @Published var treeScrollPath: String?
    @Published var treeIssues: [ScanIssue] = []
    private(set) var index: StorageIndex?
    private var reader: StorageIndex?
    private var resultReader: StorageIndex?
    private var treeReader: StorageIndex?
    private var compositionReader: StorageIndex?
    private var selectedReader: StorageIndex?
    private var cancellation: ScanCancellation?
    private var scanTask: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?
    private var mapTask: Task<Void, Never>?
    private var queryTask: Task<Void, Never>?
    private var compositionTask: Task<Void, Never>?
    private var selectedCompositionTask: Task<Void, Never>?
    private var treeTasks: [String: Task<Void, Never>] = [:]
    private var treeRequests: [String: UUID] = [:]
    private var mapGeneration = 0
    private var queryGeneration = 0
    private var selectionGeneration = 0
    private var compositionGeneration = 0
    private var projectionKey: String?
    private var compositionKey: String?
    private var mapRequestedKey: String?
    private var compositionRequestedKey: String?
    private var compositionCache: [String: ScopeComposition] = [:]
    private var lastPartialUpdate = Date.distantPast
    private var globalPlan: GlobalScanPlan?
    private var scanBaselineID: String?
    private var listOverride: String?
    private var listQueryKey: String?
    private var treePageLimits: [String: Int] = [:]
    private var treeLoadedLimits: [String: Int] = [:]
    private var treeOffsets: [String: Int] = [:]
    private var pinnedTreeEntries: [String: [StorageEntry]] = [:]
    private var treeRevision: String?
    private var history = WorkspaceHistory()
    private var restoringLocation = false
    private let developmentScope: URL?
    let dataDirectory: URL

    init() {
        let args = ProcessInfo.processInfo.arguments
        let defaults = UserDefaults.standard
        let fixtureFlag = args.firstIndex(of: "--fixture-index")
        let explicitFixturePath = fixtureFlag.flatMap { args.indices.contains($0 + 1) && args.contains("--fixture") ? args[$0 + 1] : nil }
        if let explicitFixturePath, args.contains("--verify-update-auto-install") {
            defaults.set(Bundle.main.bundleURL.path, forKey: "verification.fixtureBundlePath")
            defaults.set(explicitFixturePath, forKey: "verification.fixtureIndexPath")
        }
        let restoredFixturePath = defaults.string(forKey: "verification.fixtureBundlePath") == Bundle.main.bundleURL.path ? defaults.string(forKey: "verification.fixtureIndexPath") : nil
        let fixturePath = explicitFixturePath ?? restoredFixturePath
        isFixture = args.contains("--fixture") || fixturePath != nil
        readAccessPreferences = ReadAccessPreferences(defaults: args.contains("--fixture")
            ? UserDefaults(suiteName: "local.storageatlas.fixture")! : .standard)
        readAccessNoticeDismissed = readAccessPreferences.noticeDismissed
        if let flag = args.firstIndex(of: "--scan-path"), args.indices.contains(flag + 1) {
            developmentScope = URL(fileURLWithPath: args[flag + 1])
        } else { developmentScope = nil }
        dataDirectory = fixturePath.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? (isFixture
            ? FileManager.default.temporaryDirectory.appendingPathComponent("StorageAtlas-Preview", isDirectory: true)
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StorageAtlas", isDirectory: true))
        do {
            processLock = try IndexProcessLock(directory: dataDirectory)
            let path = dataDirectory.appendingPathComponent("storage.sqlite").path
            let store = try StorageIndex(path: path)
            index = store
            reader = try StorageIndex(path: path, readOnly: true)
            resultReader = try StorageIndex(path: path, readOnly: true)
            treeReader = try StorageIndex(path: path, readOnly: true)
            compositionReader = try StorageIndex(path: path, readOnly: true)
            selectedReader = try StorageIndex(path: path, readOnly: true)
            summary = try store.latestGlobal(preferCompleted: true) ?? store.latest()
            currentFolder = summary?.root
        } catch { self.error = "Index: \(error.localizedDescription)" }
        refreshCapacity(); reload(); checkReadAccess()
        if let developmentScope {
            Task { await Task.yield(); startFolderScan(developmentScope) }
        } else if summary?.scopeKind != .global || summary?.status != "complete" {
            if !isFixture, !args.contains("--no-auto-scan") { Task { await Task.yield(); refreshGlobal() } }
        }
    }

    var showDetails: Bool {
        get { panel == .details }
        set { if newValue { panel = .details } else if panel == .details { panel = nil } }
    }
    var showItems: Bool {
        get { panel == .results }
        set { if newValue { panel = .results } else if panel == .results { panel = nil } }
    }
    var showFolders: Bool {
        get { panel == .folders }
        set { if newValue { panel = .folders; prepareTree() } else if panel == .folders { panel = nil } }
    }
    var scope: String { summary?.scopeKind == .folder ? "Folder snapshot" : "Internal storage" }
    var scanActivityLabel: String {
        if isCancelling { return "Stopping…" }
        guard let progress else { return "Preparing…" }
        switch progress.phase {
        case .enumerating: return "Scanning"
        case .finalizing: return "Finalizing…"
        case .savingIndex: return "Saving index…"
        }
    }
    var scanActivityHelp: String {
        if isCancelling { return "Waiting for the current filesystem operation to stop." }
        switch progress?.phase {
        case .finalizing: return "Traversal ended. Finalizing measured folder totals; byte counts may remain unchanged."
        case .savingIndex: return "Committing the completed snapshot. Byte counts no longer increase during this step."
        default: return "Total work is unknown; no completion percentage is estimated."
        }
    }
    var statusLabel: String {
        if isCancelling { return "Stopping · waiting for filesystem" }
        if isScanning { return "\(scanActivityLabel) · \((progress?.fileCount ?? 0).formatted()) files" }
        guard let summary else { return "No scan" }
        switch summary.status {
        case "cancelled": return "Cancelled · partial"
        case "interrupted", "scanning": return "Interrupted · partial"
        case "complete": return summary.issueCount > 0 ? "Scan finished · \(summary.issueCount.formatted()) notes" : "Scan complete"
        default: return "\(summary.status.capitalized) · partial"
        }
    }
    var breadcrumbs: [Breadcrumb] {
        guard let scan = summary else { return [] }
        return StorageNavigation.breadcrumbs(path: currentFolder ?? scan.root, root: scan.root,
            rootTitle: scan.scopeKind == .global ? "Mac" : URL(fileURLWithPath: scan.root).lastPathComponent)
    }
    var listScopeLabel: String {
        guard let summary else { return "No snapshot" }
        let path = shortPath(queryWithin ?? summary.root)
        return listOverride != nil && search.isEmpty && category == nil ? "All files in \(path) · includes visible items" : path
    }
    var queryWithin: String? {
        guard let summary else { return nil }
        let path = (!search.isEmpty || category != nil)
            ? (searchScope == .global ? summary.root : currentFolder ?? summary.root)
            : (listOverride ?? currentFolder ?? summary.root)
        return path == "/" ? nil : path
    }
    var selectedContainerPath: String? {
        guard let selected else { return nil }
        var candidates: [String] = []
        func visit(_ nodes: [TreemapNode]) {
            for node in nodes {
                if node.path == selected.path && !node.isRollup { candidates.append(node.path) }
                else if node.children.isEmpty && StorageNavigation.contains(selected.path, in: node.path) { candidates.append(node.path) }
                visit(node.children)
            }
        }
        visit(mapNodes)
        let result = candidates.max(by: { $0.count < $1.count })
        if result == selected.path { return nil }
        if let result { return result }
        if let displayedFolder, StorageNavigation.contains(selected.path, in: displayedFolder) { return displayedFolder }
        return nil
    }
    func togglePanel(_ mode: WorkspacePanel) {
        panel = panel == mode ? nil : mode
        if panel == .folders { prepareTree() }
        if panel == .details, let selected { loadSelectedComposition(selected) }
    }
    func closePanel() { panel = nil }
    func requestSearchFocus() { searchFocusRequest += 1 }
    func clearFilters() { search = ""; category = nil; reload() }
    func loadMoreFiles() { listLimit += 200; reloadResults(preserveLimit: true) }
    func rememberListPosition(path: String?) { listScrollPath = path }
    func inspectRollup(_ node: TreemapNode) {
        listOverride = node.path; listLimit = 200; selected = nil; selectedComposition = nil
        panel = .results; reloadResults()
    }
    func refreshCapacity() {
        capacity = try? VolumeCapacity.read(at: globalPlan?.capacityURL ?? developmentScope ?? FileManager.default.homeDirectoryForCurrentUser)
    }
    func openFullDiskAccessSettings() {
        if let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"), NSWorkspace.shared.open(pane) { return }
        if let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences"), NSWorkspace.shared.open(settings) { return }
        error = "Open System Settings → Privacy & Security → Full Disk Access to review Atlas’s access."
    }
    var showReadAccessNotice: Bool {
        !isCheckingReadAccess && ReadAccessPreferences.shouldShowNotice(current: readAccess, dismissed: readAccessNoticeDismissed)
    }
    func dismissReadAccessNotice() {
        readAccessPreferences.dismissNotice()
        readAccessNoticeDismissed = true
    }
    func checkReadAccess() {
        guard !isCheckingReadAccess else { return }
        isCheckingReadAccess = true
        let paths = ReadAccessCheck.protectedUserFolders(home: FileManager.default.homeDirectoryForCurrentUser)
        Task {
            let observation = await Task.detached(priority: .utility) { ReadAccessCheck.check(paths: paths) }.value
            readAccessPreferences.save(observation)
            readAccessNoticeDismissed = readAccessPreferences.noticeDismissed
            readAccess = observation
            isCheckingReadAccess = false
        }
    }
    func refreshGlobal() {
        if let developmentScope { startFolderScan(developmentScope); return }
        guard !isScanning, !isPreparingForUpdate, let index else { return }
        beginScan(); let token = cancellation!, model = self
        scanTask = Task {
            do {
                let plan = try await Task.detached(priority: .utility) { try GlobalScanPlan.discoverStartup() }.value
                globalPlan = plan; refreshCapacity()
                let result = try await Task.detached(priority: .utility) {
                    try ScanEngine.scan(global: plan, index: index, cancellation: token) { update in
                        Task { @MainActor in model.receive(update, token: token) }
                    }
                }.value
                await accept(result)
            } catch { self.error = "Scan: \(error.localizedDescription)" }
            endScan()
        }
    }
    private func startFolderScan(_ url: URL) {
        guard !isScanning, !isPreparingForUpdate, let index else { return }
        beginScan(); let token = cancellation!, model = self
        scanTask = Task {
            do {
                let result = try await Task.detached(priority: .utility) {
                    try ScanEngine.scan(root: url, index: index, cancellation: token) { update in
                        Task { @MainActor in model.receive(update, token: token) }
                    }
                }.value
                await accept(result)
            } catch { self.error = "Scan: \(error.localizedDescription)" }
            endScan()
        }
    }
    private func beginScan() {
        maintenanceTask?.cancel(); maintenanceTask = nil
        isScanning = true; isCancelling = false; progress = nil; error = nil; lastPartialUpdate = .distantPast
        scanBaselineID = mapNodes.isEmpty ? nil : summary?.id
        cancellation = ScanCancellation()
    }
    private func receive(_ update: ScanProgress, token: ScanCancellation) {
        guard cancellation === token else { return }
        progress = update
        guard scanBaselineID == nil,
              loadingFolder == nil, Date().timeIntervalSince(lastPartialUpdate) >= 2,
              let id = update.scanID, let reader else { return }
        lastPartialUpdate = Date()
        Task {
            do {
                let partial = try await Task.detached(priority: .utility) { try reader.summary(id: id) }.value
                guard cancellation === token, let partial else { return }
                let newScan = summary?.id != partial.id
                summary = partial
                if newScan { currentFolder = partial.root; selected = nil; history.reset(); updateHistoryFlags() }
                reload()
            } catch { /* The final scan result reports persistent failures. */ }
        }
    }
    private func accept(_ result: ScanSummary) async {
        if result.status != "complete", let baseline = scanBaselineID, baseline == summary?.id {
            error = "Refresh cancelled. Showing the previous measured snapshot."
            return
        }
        guard result.status == "complete" || summary?.status != "complete" || summary?.scopeKind != result.scopeKind else {
            error = "Refresh cancelled. Showing the previous completed scan."; return
        }
        let previous = currentFolder ?? result.root
        let previousSelection = selected?.path
        guard let reader else { summary = result; currentFolder = result.root; return }
        let restored = await Task.detached(priority: .utility) {
            var path = StorageNavigation.contains(previous, in: result.root) ? previous : result.root
            while path != result.root {
                if let entry = try? reader.entry(scanID: result.id, path: path), entry.isDirectory { break }
                path = URL(fileURLWithPath: path).deletingLastPathComponent().path
            }
            let selection = previousSelection.flatMap { try? reader.entry(scanID: result.id, path: $0) }
            return (path, selection)
        }.value
        summary = result; currentFolder = restored.0
        if previous != restored.0 { error = "Previous folder is not in this snapshot. Showing \(shortPath(restored.0))." }
        selected = restored.1; selectedComposition = nil; treeSelectedPath = restored.1?.path ?? restored.0
        history.reset(); updateHistoryFlags()
        compositionCache.removeAll(); compositionKey = nil
        if panel == .details, let selected { loadSelectedComposition(selected) }
    }
    private func endScan() {
        isScanning = false; isCancelling = false; cancellation = nil; scanTask = nil; projectionKey = nil
        scanBaselineID = nil
        refreshCapacity(); reload()
        scheduleIndexMaintenance()
    }
    private func scheduleIndexMaintenance() {
        guard maintenanceTask == nil, let index else { return }
        maintenanceTask = Task {
            do {
                while !Task.isCancelled, !isScanning {
                    let more = try await Task.detached(priority: .background) {
                        try index.pruneObsoleteSnapshotBatch()
                    }.value
                    if !more { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
            } catch is CancellationError {
                // The next scan takes priority. Committed maintenance batches are resumable.
            } catch {
                if !Task.isCancelled { self.error = "Snapshot saved. Old index maintenance could not finish: \(error.localizedDescription)" }
            }
            // A cancelled task must not clear a newer maintenance task's handle.
            if !Task.isCancelled { maintenanceTask = nil }
        }
    }
    func cancelScan() { guard isScanning else { return }; isCancelling = true; cancellation?.cancel() }

    func prepareForUpdate() async {
        guard !isScanning, !isPreparingForUpdate else { return }
        isPreparingForUpdate = true
        maintenanceTask?.cancel()
        if let maintenanceTask { await maintenanceTask.value }
        mapTask?.cancel(); queryTask?.cancel(); compositionTask?.cancel(); selectedCompositionTask?.cancel()
        treeTasks.values.forEach { $0.cancel() }
        mapGeneration += 1; queryGeneration += 1; compositionGeneration += 1; selectionGeneration += 1
        let connections = [index, reader, resultReader, treeReader, compositionReader, selectedReader].compactMap { $0 }
        connections.forEach { $0.interruptReadQueries() }
        await Task.detached(priority: .utility) { connections.forEach { $0.closeForAppUpdate() } }.value
    }

    func resumeAfterFailedUpdate() {
        guard isPreparingForUpdate else { return }
        do {
            let path = dataDirectory.appendingPathComponent("storage.sqlite").path
            index = try StorageIndex(path: path)
            reader = try StorageIndex(path: path, readOnly: true)
            resultReader = try StorageIndex(path: path, readOnly: true)
            treeReader = try StorageIndex(path: path, readOnly: true)
            compositionReader = try StorageIndex(path: path, readOnly: true)
            selectedReader = try StorageIndex(path: path, readOnly: true)
            isPreparingForUpdate = false; projectionKey = nil; compositionKey = nil; reload()
        } catch { self.error = "Reopen Atlas to restore index access: \(error.localizedDescription)" }
    }

    private func location() -> WorkspaceLocation {
        WorkspaceLocation(folder: currentFolder ?? summary?.root ?? "/", selectedPath: selected?.path,
            search: search, searchScope: searchScope, category: category, panel: panel,
            expandedPaths: treeExpanded, treePageLimits: treePageLimits, treeScrollPath: treeScrollPath,
            listScrollPath: listScrollPath, listLimit: listLimit, listOverride: listOverride)
    }
    private func updateHistoryFlags() { canGoBack = history.canGoBack; canGoForward = history.canGoForward }
    func navigate(_ path: String) {
        guard let root = summary?.root, StorageNavigation.contains(path, in: root) else { return }
        if currentFolder != path { history.record(location()); updateHistoryFlags() }
        currentFolder = path; selected = nil; selectedComposition = nil; selectionGeneration += 1
        hoveredPath = nil; hoveredNode = nil; listOverride = nil; listScrollPath = nil
        if panel == .details { panel = nil }
        treeSelectedPath = path; treeScrollPath = path
        reload(); if panel == .folders { prepareTree(revealFocus: true) }
    }
    func goBack() { if let state = history.back(from: location()) { restore(state) }; updateHistoryFlags() }
    func goForward() { if let state = history.forward(from: location()) { restore(state) }; updateHistoryFlags() }
    private func restore(_ state: WorkspaceLocation) {
        restoringLocation = true
        defer { restoringLocation = false }
        selectionGeneration += 1
        treeTasks.values.forEach { $0.cancel() }; treeTasks.removeAll(); treeRequests.removeAll(); treeLoading.removeAll()
        currentFolder = state.folder; search = state.search; searchScope = state.searchScope; category = state.category
        treeExpanded = state.expandedPaths; treePageLimits = state.treePageLimits
        for path in Array(treeChildren.keys) {
            let limit = treePageLimits[path] ?? 200
            if (treeOffsets[path] ?? 0) > limit { treeHasMore.insert(path) }
            treeChildren[path] = Array((treeChildren[path] ?? []).prefix(limit))
            treeLoadedLimits[path] = min(treeLoadedLimits[path] ?? 0, limit)
            treeOffsets[path] = min(treeOffsets[path] ?? 0, limit)
        }
        treeScrollPath = state.treeScrollPath; listScrollPath = state.listScrollPath
        listLimit = state.listLimit; listOverride = state.listOverride; listQueryKey = nil
        selected = nil; selectedComposition = nil; hoveredNode = nil; hoveredPath = nil
        treeSelectedPath = state.selectedPath ?? state.folder
        panel = state.panel
        reload(preserveListLimit: true)
        if let path = state.selectedPath { selectPath(path, forceDetails: false) }
        if panel == .folders { prepareTree() }
    }
    func goUp() {
        guard let folder = currentFolder, let root = summary?.root, folder != root else { return }
        navigate(URL(fileURLWithPath: folder).deletingLastPathComponent().path)
    }
    func goGlobal() { if let root = summary?.root { navigate(root) } }
    func select(_ entry: StorageEntry) {
        selectionGeneration += 1
        selected = entry; treeSelectedPath = entry.path
        if panel != .folders { panel = .details }
        loadSelectedComposition(entry)
    }
    func inspect(_ entry: StorageEntry) { selectionGeneration += 1; selected = entry; treeSelectedPath = entry.path; panel = .details; loadSelectedComposition(entry) }
    func inspectSelected() { if let selected { inspect(selected) } }
    func selectTreeEntry(_ entry: StorageEntry) { selectionGeneration += 1; selected = entry; treeSelectedPath = entry.path; if panel == .details { loadSelectedComposition(entry) } }
    func activateTreeEntry(_ entry: StorageEntry) { if entry.isDirectory { navigate(entry.path) } else { inspect(entry) } }
    func openContainingFolder(_ entry: StorageEntry) { navigate(entry.isDirectory ? entry.path : entry.parent) }
    func selectPath(_ path: String) { selectPath(path, forceDetails: true) }
    private func selectPath(_ path: String, forceDetails: Bool) {
        guard let scan = summary, let reader else { return }
        selectionGeneration += 1; let generation = selectionGeneration
        Task {
            do {
                let entry = try await Task.detached(priority: .userInitiated) { try reader.entry(scanID: scan.id, path: path) }.value
                guard generation == selectionGeneration, summary?.id == scan.id, let entry else { return }
                if forceDetails { select(entry) } else { selected = entry; loadSelectedComposition(entry) }
            } catch { self.error = "Item: \(error.localizedDescription)" }
        }
    }
    private func locationAvailable(_ entry: StorageEntry) -> Bool {
        var info = stat()
        guard lstat(entry.path, &info) == 0 else {
            error = "Location unavailable: \(shortPath(entry.path)). The snapshot may be outdated or access may have changed. Refresh to check it again."
            return false
        }
        return true
    }
    func reveal(_ entry: StorageEntry) { if locationAvailable(entry) { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) } }
    func copyPath(_ entry: StorageEntry) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.path, forType: .string) }
    func dismissTransient() {
        if showCoverage { showCoverage = false }
        else if panel != nil { panel = nil }
        else if !search.isEmpty { search = ""; reload() }
        else if category != nil { category = nil; reload() }
        else { selected = nil }
    }

    func reload(preserveListLimit: Bool = false) {
        guard !isPreparingForUpdate else { return }
        reloadMap(); reloadResults(preserveLimit: preserveListLimit); reloadComposition()
        if panel == .folders { prepareTree() }
    }
    private func reloadMap() {
        guard let reader, let scan = summary else { return }
        let folder = currentFolder ?? scan.root
        let key = "\(scan.id):\(folder):\(scan.allocatedBytes):\(scan.logicalBytes):\(scan.fileCount):\(scan.issueCount):\(scan.status)"
        if key == mapRequestedKey && loadingFolder != nil { return }
        mapGeneration += 1; let generation = mapGeneration
        mapTask?.cancel()
        mapRequestedKey = key
        guard key != projectionKey else { loadingFolder = nil; return }
        loadingFolder = folder
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try TreemapProjection.load(index: reader, scanID: scan.id, rootPath: folder, maxDepth: folder == scan.root ? 4 : 1)
        }
        mapTask = Task {
            do {
                let nodes = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
                guard generation == mapGeneration else { return }
                mapNodes = nodes; displayedFolder = folder; loadingFolder = nil; projectionKey = key
            } catch {
                guard generation == mapGeneration else { return }
                loadingFolder = nil; self.error = "Map: \(error.localizedDescription)"
            }
        }
    }
    private func reloadResults(preserveLimit: Bool = false) {
        guard let index = resultReader, let scan = summary else { return }
        queryGeneration += 1; let generation = queryGeneration
        queryTask?.cancel()
        let query = search, category = category, within = queryWithin
        let key = "\(scan.id):\(within ?? "*"):\(query):\(category?.rawValue ?? "*")"
        if key != listQueryKey {
            if !preserveLimit { listLimit = 200 }
            listEntries = []; listHasMore = false; matchingPaths = []
            listQueryKey = key
        }
        let limit = listLimit
        isQuerying = true
        queryTask = Task {
            guard !Task.isCancelled else { return }
            let work = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let rows = try index.largestFiles(scanID: scan.id, search: query, category: category, within: within, limit: limit + 1)
                try Task.checkCancellation()
                let matches = try index.matchingPaths(scanID: scan.id, search: query, category: category, within: within)
                try Task.checkCancellation()
                let issues = try index.issues(scanID: scan.id)
                return (rows, matches, issues)
            }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel(); index.interruptReadQueries() })
                guard generation == queryGeneration else { return }
                if self.error?.hasPrefix("Results:") == true { self.error = nil }
                listEntries = Array(result.0.prefix(limit)); listHasMore = result.0.count > limit
                matchingPaths = result.1; issues = result.2; isQuerying = false
                treeIssues = issues.filter { StorageNavigation.contains($0.path, in: currentFolder ?? scan.root) }
            } catch {
                guard generation == queryGeneration else { return }
                isQuerying = false; self.error = "Results: \(error.localizedDescription)"
            }
        }
    }
    private func reloadComposition() {
        guard let index = compositionReader, let scan = summary else { return }
        let folder = currentFolder ?? scan.root
        let key = "\(scan.id):\(folder):\(scan.allocatedBytes):\(scan.logicalBytes):\(scan.fileCount):\(scan.issueCount):\(scan.status)"
        if key == compositionRequestedKey && isLoadingComposition { return }
        compositionGeneration += 1; let generation = compositionGeneration
        compositionTask?.cancel()
        compositionRequestedKey = key
        guard key != compositionKey else { composition = compositionCache[key]; isLoadingComposition = false; return }
        composition = nil; isLoadingComposition = true
        if let cached = compositionCache[key] { composition = cached; compositionKey = key; isLoadingComposition = false; return }
        compositionTask = Task {
            guard !Task.isCancelled else { return }
            let work = Task.detached(priority: .utility) { try Task.checkCancellation(); return try index.composition(scanID: scan.id, within: folder) }
            do {
                let value = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel(); index.interruptReadQueries() })
                guard generation == compositionGeneration else { return }
                if self.error?.hasPrefix("Composition:") == true { self.error = nil }
                composition = value; compositionKey = key; isLoadingComposition = false
                if compositionCache.count > 30 { compositionCache.removeAll() }
                compositionCache[key] = value
            } catch {
                guard generation == compositionGeneration else { return }
                isLoadingComposition = false; self.error = "Composition: \(error.localizedDescription)"
            }
        }
    }
    private func loadSelectedComposition(_ entry: StorageEntry) {
        selectedCompositionTask?.cancel()
        selectedComposition = nil
        guard entry.isDirectory, let scan = summary, let index = selectedReader else { return }
        let key = "\(scan.id):\(entry.path):\(scan.allocatedBytes):\(scan.logicalBytes):\(scan.fileCount):\(scan.issueCount):\(scan.status)"
        if let cached = compositionCache[key] { selectedComposition = cached; return }
        selectedCompositionTask = Task {
            guard !Task.isCancelled else { return }
            let work = Task.detached(priority: .utility) { try Task.checkCancellation(); return try index.composition(scanID: scan.id, within: entry.path) }
            do {
                let value = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel(); index.interruptReadQueries() })
                guard summary?.id == scan.id, selected?.path == entry.path,
                      summary?.allocatedBytes == scan.allocatedBytes, summary?.logicalBytes == scan.logicalBytes,
                      summary?.fileCount == scan.fileCount, summary?.issueCount == scan.issueCount,
                      summary?.status == scan.status else { return }
                selectedComposition = value; compositionCache[key] = value
            } catch { /* Main-scope composition remains independently available. */ }
        }
    }

    private func prepareTree(revealFocus: Bool = false) {
        guard let scan = summary else { return }
        let revision = "\(scan.id):\(scan.allocatedBytes):\(scan.logicalBytes):\(scan.fileCount):\(scan.issueCount):\(scan.status)"
        let refreshPaths = treeRevision != revision ? Set(treeChildren.keys).union(treeExpanded) : []
        if treeRevision != revision {
            treeTasks.values.forEach { $0.cancel() }; treeTasks.removeAll()
            treeChildren.removeAll(); treeLoadedLimits.removeAll(); treeHasMore.removeAll(); treeLoading.removeAll()
            treeOffsets.removeAll(); pinnedTreeEntries.removeAll()
            treeRequests.removeAll()
            treeRoot = nil; treeRevision = revision
            for path in refreshPaths where StorageNavigation.contains(path, in: scan.root) {
                loadTreeChildren(path: path)
            }
        }
        for crumb in breadcrumbs {
            if revealFocus { treeExpanded.insert(crumb.path) }
            loadTreeChildren(path: crumb.path)
        }
        let crumbs = breadcrumbs, folder = currentFolder
        if let index = treeReader {
            Task {
                let entries = await Task.detached(priority: .userInitiated) { crumbs.dropFirst().compactMap { try? index.entry(scanID: scan.id, path: $0.path) } }.value
                guard summary?.id == scan.id, currentFolder == folder, treeRevision == revision else { return }
                for entry in entries {
                    var pins = pinnedTreeEntries[entry.parent] ?? []
                    pins.removeAll { $0.path == entry.path }; pins.append(entry)
                    pinnedTreeEntries[entry.parent] = pins
                    mergePinnedEntries(parent: entry.parent)
                }
            }
        }
        if treeSelectedPath == nil { treeSelectedPath = currentFolder ?? scan.root }
    }
    func loadTreeChildren(path: String) { fetchTreeChildren(path: path, force: false) }
    private func fetchTreeChildren(path: String, force: Bool) {
        guard let scan = summary, let index = treeReader, StorageNavigation.contains(path, in: scan.root) else { return }
        let limit = treePageLimits[path] ?? 200
        if !force, (treeLoadedLimits[path] ?? 0) >= limit || treeLoading.contains(path) { return }
        treeTasks[path]?.cancel(); treeLoading.insert(path)
        let requestID = UUID(); treeRequests[path] = requestID
        let offset = force ? (treeOffsets[path] ?? 0) : 0
        let existing = force ? (treeChildren[path] ?? []) : []
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            var entries: [StorageEntry] = [], hasMore = true
            repeat {
                try Task.checkCancellation()
                let page = try index.children(scanID: scan.id, parent: path, limit: min(1000, max(1, limit - offset - entries.count)), offset: offset + entries.count)
                entries.append(contentsOf: page.entries); hasMore = page.hasMore
            } while hasMore && offset + entries.count < limit
            let page = TreePage(entries: entries, hasMore: hasMore)
            let root = path == scan.root ? try index.entry(scanID: scan.id, path: path) : nil
            return (page, root)
        }
        treeTasks[path] = Task {
            do {
                let value = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
                guard summary?.id == scan.id, treeRequests[path] == requestID else { return }
                var merged = Dictionary(uniqueKeysWithValues: existing.map { ($0.path, $0) })
                for entry in value.0.entries { merged[entry.path] = entry }
                treeChildren[path] = Array(merged.values); mergePinnedEntries(parent: path)
                treeOffsets[path] = offset + value.0.entries.count; treeLoadedLimits[path] = limit
                if value.0.hasMore { treeHasMore.insert(path) } else { treeHasMore.remove(path) }
                if let root = value.1 { treeRoot = root }
                treeLoading.remove(path); treeTasks[path] = nil
            } catch {
                guard summary?.id == scan.id, treeRequests[path] == requestID else { return }
                treeLoading.remove(path); treeTasks[path] = nil
                if !(error is CancellationError) { self.error = "Folders: \(error.localizedDescription)" }
            }
        }
    }
    private func mergePinnedEntries(parent: String) {
        var entries = Dictionary(uniqueKeysWithValues: (treeChildren[parent] ?? []).map { ($0.path, $0) })
        for pin in pinnedTreeEntries[parent] ?? [] { entries[pin.path] = pin }
        treeChildren[parent] = entries.values.sorted { $0.allocatedBytes == $1.allocatedBytes ? $0.path < $1.path : $0.allocatedBytes > $1.allocatedBytes }
    }
    func loadMoreTree(path: String) { treePageLimits[path] = (treePageLimits[path] ?? 200) + 200; fetchTreeChildren(path: path, force: true) }
    func toggleTreeExpansion(path: String) {
        if treeExpanded.contains(path) { treeExpanded.remove(path) }
        else { treeExpanded.insert(path); loadTreeChildren(path: path) }
    }
    func treeParentBytes(path: String) -> Int64? {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        if parent == summary?.root { return treeRoot?.allocatedBytes ?? summary?.allocatedBytes }
        if path == summary?.root { return nil }
        return treeChildren.values.lazy.flatMap { $0 }.first(where: { $0.path == parent })?.allocatedBytes
    }
}

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}
func byteString(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
func shortPath(_ path: String) -> String {
    let home = NSHomeDirectory()
    return path == home ? "~" : (path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path)
}
