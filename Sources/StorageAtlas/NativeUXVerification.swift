import AppKit
import Foundation
import StorageCore

/// Opt-in checks of actual native controls backed by the loaded metadata snapshot.
@MainActor enum NativeUXVerification {
    private static var started = false
    static func runIfRequested(model: AppModel) async {
        let args = ProcessInfo.processInfo.arguments
        guard !started, let flag = args.firstIndex(of: "--verify-ux"), args.indices.contains(flag + 1) else { return }
        started = true
        let output = URL(fileURLWithPath: args[flag + 1], isDirectory: true)
        var evidence: [String: Any] = ["result": "running", "fixture": args.contains("--fixture")]
        func save() {
            if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: output.appendingPathComponent("ux-verification.json"))
            }
        }
        func check(_ name: String, _ passed: Bool) throws {
            evidence[name] = passed; save()
            if !passed { throw UXVerificationError(message: name + " failed") }
        }
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true); save()
            evidence["reduceMotionEffective"] = MapStyle.reduceMotion
            evidence["reduceMotionApplicationOverride"] = args.contains("--reduce-motion")
            if args.contains("--reduce-motion") { try check("reduceMotionOverrideIsEffective", MapStyle.reduceMotion) }
            try await waitUntil { !model.isScanning && model.summary != nil && !model.mapNodes.isEmpty && model.loadingFolder == nil }
            guard let window = NSApp.windows.first(where: { $0.contentView != nil && !($0 is NSPanel) }), let content = window.contentView else { throw UXVerificationError(message: "Native window unavailable") }
            if args.contains("--verify-coverage-only") {
                try await waitUntil { !model.isCheckingReadAccess && model.readAccess != nil }
                evidence["readAccessState"] = model.readAccess?.state.rawValue
                evidence["readAccessNoticeVisible"] = model.showReadAccessNotice
                try check("readableFoldersDoNotRequestAccess", model.readAccess?.state != .available || !model.showReadAccessNotice)
                try check("unknownAccessDoesNotRequestAccess", model.readAccess?.state != .unknown || !model.showReadAccessNotice)
                try check("coverageNotesAvailable", (model.summary?.issueCount ?? 0) > 0)
                for (name, size) in [("normal", NSSize(width: 1440, height: 900)), ("compact", NSSize(width: 960, height: 632))] {
                    window.setContentSize(size)
                    try await pause()
                    try capture(window, output.appendingPathComponent("\(name).png"))
                }
                model.showCoverage = true
                try await pause()
                guard let popover = NSApp.windows.first(where: { $0 !== window && $0.isVisible && ($0.contentView?.bounds.width ?? 0) >= 400 }) else {
                    throw UXVerificationError(message: "Coverage popover unavailable")
                }
                try capture(popover, output.appendingPathComponent("coverage.png"))
                evidence["coveragePopoverCaptured"] = true
                evidence["result"] = "completed"
                evidence["finished"] = ISO8601DateFormatter().string(from: Date())
                save()
                return
            }
            window.setContentSize(NSSize(width: 1440, height: 900))
            model.goGlobal(); model.clearFilters(); model.closePanel()
            try await settle(model)
            guard let surface = find(StorageMapSurface.self, in: content), let scan = model.summary else { throw UXVerificationError(message: "Native storage map missing") }
            let initialBounds = surface.bounds
            evidence["scope"] = scan.scopeKind.rawValue; evidence["status"] = scan.status
            evidence["files"] = scan.fileCount; evidence["allocatedBytes"] = scan.allocatedBytes
            evidence["mapBytes"] = model.mapNodes.reduce(Int64(0)) { $0 + $1.bytes }
            evidence["usableMapFraction"] = surface.bounds.width * surface.bounds.height / (content.safeAreaRect.width * content.safeAreaRect.height)
            evidence["normalWindowGeometry"] = geometry(surface: surface, content: content)
            try check("mapConservesSnapshot", model.mapNodes.reduce(Int64(0)) { $0 + $1.bytes } == scan.allocatedBytes)
            try check("normalMapOccupiesAtLeast85Percent", surface.bounds.width * surface.bounds.height >= content.safeAreaRect.width * content.safeAreaRect.height * 0.85)
            try capture(window, output.appendingPathComponent("global.png"))
            model.hoveredNode = model.mapNodes.first
            model.hoveredPath = model.hoveredNode?.path
            try await pause()
            try capture(window, output.appendingPathComponent("hover.png"))
            model.hoveredNode = nil; model.hoveredPath = nil
            model.showCoverage = true
            try await settle(model)
            evidence["coverageWindowInventory"] = NSApp.windows.map { candidate in
                ["class": candidate.className, "visible": candidate.isVisible,
                 "mainWorkspace": candidate === window, "frame": NSStringFromRect(candidate.frame),
                 "content": NSStringFromRect(candidate.contentView?.bounds ?? .zero)] as [String: Any]
            }
            if let coverageWindow = NSApp.windows.first(where: { candidate in
                guard candidate !== window, candidate.isVisible, let bounds = candidate.contentView?.bounds else { return false }
                return bounds.width >= 400 && bounds.height >= 400
            }) {
                try capture(coverageWindow, output.appendingPathComponent("coverage.png"))
                evidence["coveragePopoverCaptured"] = true
                evidence["coverageWindowClass"] = coverageWindow.className
            } else {
                evidence["coveragePopoverCaptured"] = false
                evidence["coverageCaptureLimit"] = "No separate visible native coverage window of at least 400 by 400 points was exposed to the application capture helper."
            }
            save()
            model.showCoverage = false
            try await pause()

            model.togglePanel(.folders)
            try await waitUntil { model.treeRoot != nil && model.treeLoading.isEmpty }
            try await settle(model)
            guard let outline = find(NSOutlineView.self, in: content) else { throw UXVerificationError(message: "Native folder outline missing") }
            try check("treeDoesNotResizeMap", surface.bounds == initialBounds)
            let focus = model.currentFolder
            if let rootItem = outline.item(atRow: 0) {
                outline.collapseItem(rootItem); try await pause()
                try check("nativeCollapsePreservesFocus", model.currentFolder == focus && !model.treeExpanded.contains(scan.root))
                outline.expandItem(rootItem); try await pause()
                try check("nativeExpansionPreservesFocus", model.currentFolder == focus && model.treeExpanded.contains(scan.root))
            }
            try capture(window, output.appendingPathComponent("folders.png"))
            guard let first = model.treeChildren[scan.root]?.first(where: \.isDirectory) else { throw UXVerificationError(message: "No real directory to exercise") }
            model.treeSelectedPath = first.path
            try await pause()
            window.makeFirstResponder(outline)
            if let enter = key(36, window, "\r") { outline.keyDown(with: enter) }
            try await settle(model)
            try check("nativeTreeReturnEntersFolder", model.currentFolder == first.path)
            try check("treeModeSurvivesNavigation", model.panel == .folders)
            try check("breadcrumbSegmentsMatchPath", model.breadcrumbs.last?.path == model.currentFolder && model.breadcrumbs.first?.path == scan.root)
            try capture(window, output.appendingPathComponent("folder-contents.png"))
            if args.contains("--fixture") {
                model.inspect(first)
                try await waitUntil { model.selectedComposition != nil }
                try await settle(model)
                try check("mixedFolderHasMeasuredComposition", model.selectedComposition?.isMixed == true)
                try capture(window, output.appendingPathComponent("mixed-folder-details.png"))
                model.togglePanel(.folders); try await settle(model)
            }

            var measuredNavigation: [Double] = []
            for _ in 0..<3 {
                guard let folder = model.currentFolder else { break }
                model.loadTreeChildren(path: folder)
                try await waitUntil { !model.treeLoading.contains(folder) }
                guard let child = model.treeChildren[folder]?.first(where: \.isDirectory) else { break }
                let start = Date(); model.activateTreeEntry(child)
                try await waitUntil { model.loadingFolder == nil && model.displayedFolder == child.path }
                measuredNavigation.append(Date().timeIntervalSince(start) * 1000)
            }
            evidence["navigationMilliseconds"] = measuredNavigation
            evidence["enteredFolderLevels"] = measuredNavigation.count + 1
            try await settle(model)
            if let deepOutline = find(NSOutlineView.self, in: content) {
                let shares = parentShareGeometry(deepOutline)
                evidence["deepTreeParentShareGeometry"] = shares
                try check("deepTreeNumbersFitNativeViewport", !shares.isEmpty && shares.allSatisfy { $0["fitsHorizontally"] as? Bool == true })
            }
            try capture(window, output.appendingPathComponent("deep-folder.png"))

            // Returning to the last successfully displayed scope must invalidate a
            // pending navigation even when its cached map key already matches.
            let stable = model.currentFolder!
            model.navigate(scan.root); model.goBack()
            try await settle(model)
            try check("rapidBackKeepsMapAndBreadcrumbAligned", model.currentFolder == stable && model.displayedFolder == stable)
            try check("forwardIsAvailable", model.canGoForward)

            model.search = "__atlas_no_such_name__"; model.searchScope = .folder
            model.category = .development; model.reload()
            try await settle(model)
            let savedExpansion = model.treeExpanded
            model.treeScrollPath = stable
            model.navigate(scan.root)
            try await settle(model)
            model.goBack(); try await settle(model)
            try check("historyRestoresFiltersAndTree", model.currentFolder == stable && model.search == "__atlas_no_such_name__" && model.searchScope == .folder && model.category == .development && model.treeExpanded == savedExpansion && model.panel == .folders)
            model.clearFilters(); try await settle(model)

            model.goGlobal(); model.panel = .results
            try await settle(model)
            guard let target = model.listEntries.first else { throw UXVerificationError(message: "No indexed file for scoped search") }
            let tiles = TreemapLayout.layout(nodes: model.mapNodes, in: surface.bounds).tiles
            if let hidden = model.listEntries.first(where: { entry in !tiles.contains(where: { !$0.node.isRollup && $0.node.path == entry.path }) }) {
                model.inspect(hidden); try await settle(model)
                try check("hiddenFileNamesItsContainer", model.selectedContainerPath != nil)
                try capture(window, output.appendingPathComponent("contained-file.png"))
                model.panel = .results
            }
            if let other = model.listEntries.dropFirst().first {
                model.selectPath(target.path); model.selectTreeEntry(other)
                try await pause()
                try check("lateLookupDoesNotOverwriteDirectSelection", model.selected?.path == other.path)
            }
            let topFolder = model.treeChildren[scan.root]?.first(where: { $0.isDirectory && !StorageNavigation.contains(target.path, in: $0.path) })
            if let topFolder {
                model.navigate(topFolder.path); model.searchScope = .folder; model.search = target.path; model.reload()
                try await settle(model)
                try check("localSearchExcludesExternalResult", !model.listEntries.contains(where: { $0.path == target.path }))
                model.searchScope = .global; model.reload(); try await settle(model)
                try check("globalSearchFindsExternalResult", model.listEntries.contains(where: { $0.path == target.path }))
                model.openContainingFolder(target); try await settle(model)
                try check("resultOpensActualContainingFolder", model.currentFolder == target.parent)
                model.goBack(); try await settle(model)
                try check("resultBackRestoresOriginAndQuery", model.currentFolder == topFolder.path && model.search == target.path && model.searchScope == .global)
            }
            model.clearFilters(); model.navigate(target.parent); model.showFolders = true
            try await settle(model)
            model.select(target); try await settle(model)
            try check("mapSelectionPreservesOpenTree", model.panel == .folders && model.selected?.path == target.path)
            model.inspectSelected(); try await settle(model)
            try check("explicitInspectOpensDetails", model.panel == .details)
            try capture(window, output.appendingPathComponent("details.png"))
            model.togglePanel(.folders); try await settle(model)
            try check("returnToTreePreservesScope", model.currentFolder == target.parent && model.treeExpanded.contains(target.parent))

            model.goGlobal(); model.clearFilters(); try await settle(model, composition: true)
            if let composition = model.composition {
                evidence["classificationVersion"] = composition.classificationVersion
                try check("compositionCountsFilesOnce", composition.allocatedBytes == scan.allocatedBytes && composition.fileCount == scan.fileCount)
                evidence["compositionCategories"] = composition.totals.map { $0.category.rawValue }
            }
            let categoryStart = Date()
            model.category = .development; model.panel = .results; model.reload()
            try await waitUntil { !model.isQuerying }
            evidence["categoryQueryMilliseconds"] = Date().timeIntervalSince(categoryStart) * 1000
            evidence["categoryMatchedPaths"] = model.matchingPaths.count
            try await settle(model)
            evidence["categoryMapReadyMilliseconds"] = Date().timeIntervalSince(categoryStart) * 1000
            try check("categoryHasNoQueryError", model.error == nil)
            try check("categoryResultsMatchEvidence", !model.listEntries.isEmpty && model.listEntries.allSatisfy { $0.category == .development })
            try capture(window, output.appendingPathComponent("category-results.png"))
            model.clearFilters(); model.showFolders = true
            try await settle(model)
            if let crowded = model.treeChildren[scan.root]?.first(where: { $0.name == "many-files" && $0.isDirectory }) {
                model.activateTreeEntry(crowded); try await settle(model)
                model.loadTreeChildren(path: crowded.path)
                try await waitUntil { !model.treeLoading.contains(crowded.path) }
                let initial = model.treeChildren[crowded.path]?.count ?? 0
                if let currentOutline = find(NSOutlineView.self, in: content), currentOutline.numberOfRows > 30, let scroll = currentOutline.enclosingScrollView {
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: currentOutline.rect(ofRow: 25).minY))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
                    try await pause()
                }
                let savedTreeAnchor = model.treeScrollPath
                model.navigate(scan.root); try await settle(model)
                model.navigate(crowded.path); try await settle(model)
                for _ in 0..<5 {
                    model.loadMoreTree(path: crowded.path)
                    try await waitUntil { !model.treeLoading.contains(crowded.path) }
                }
                try check("treePaginationBeyondThousand", (model.treeChildren[crowded.path]?.count ?? 0) > 1000)
                model.goBack(); try await settle(model)
                model.goBack(); try await settle(model)
                try check("historyRestoresTreePageLimit", (model.treeChildren[crowded.path]?.count ?? 0) == initial)
                try check("historyRestoresTreeScrollAnchor", model.treeScrollPath == savedTreeAnchor)
                model.loadMoreTree(path: crowded.path)
                try await waitUntil { !model.treeLoading.contains(crowded.path) }
                evidence["zeroAllocationTreeRecords"] = model.treeChildren[crowded.path]?.filter { $0.allocatedBytes == 0 }.count
                try capture(window, output.appendingPathComponent("tree-pagination.png"))
            }
            if args.contains("--fixture") {
                if let denied = model.treeChildren[scan.root]?.first(where: { $0.name == "no-access" }) {
                    model.activateTreeEntry(denied); try await settle(model)
                    try check("deniedScopeKeepsUnknownState", model.mapNodes.isEmpty && model.issues.contains(where: { $0.path == denied.path }))
                    guard let currentOutline = find(NSOutlineView.self, in: content) else { throw UXVerificationError(message: "Current tree missing") }
                    let visible = currentOutline.rows(in: currentOutline.visibleRect)
                    let selectedRow = currentOutline.selectedRow
                    evidence["focusedTreeDiagnostics"] = ["selectedRow": selectedRow, "visibleStart": visible.location, "visibleCount": visible.length,
                        "modelSelected": model.treeSelectedPath ?? "nil", "scrollPath": model.treeScrollPath ?? "nil", "rows": currentOutline.numberOfRows,
                        "rowPath": selectedRow >= 0 ? currentOutline.view(atColumn: 0, row: selectedRow, makeIfNecessary: true)?.toolTip ?? "nil" : "nil",
                        "attached": currentOutline.window === window,
                        "frame": NSStringFromRect(currentOutline.frame), "bounds": NSStringFromRect(currentOutline.bounds),
                        "visible": NSStringFromRect(currentOutline.visibleRect), "clip": NSStringFromRect(currentOutline.enclosingScrollView?.contentView.bounds ?? .zero),
                        "rowRect": selectedRow >= 0 ? NSStringFromRect(currentOutline.rect(ofRow: selectedRow)) : "nil"]
                    try check("focusedTreeRowIsVisible", currentOutline.window === window && model.treeSelectedPath == denied.path && selectedRow >= 0 && visible.contains(selectedRow)
                        && currentOutline.view(atColumn: 0, row: selectedRow, makeIfNecessary: true)?.toolTip == denied.path)
                    try capture(window, output.appendingPathComponent("no-access.png"))
                }
                model.navigate(target.parent); model.selectTreeEntry(target)
                try await settle(model)
                let baseline = model.summary?.id
                model.refreshGlobal(); model.cancelScan()
                try await waitUntil { !model.isScanning }
                try await settle(model)
                try check("cancelPreservesMeasuredBaselineAndFocus", model.summary?.id == baseline && model.currentFolder == target.parent)
                model.refreshGlobal()
                try await waitUntil { !model.isScanning }
                try await settle(model)
                try check("refreshPreservesExistingFocusAndSelection", model.summary?.id != baseline && model.currentFolder == target.parent && model.selected?.path == target.path)
                model.error = nil
            }
            model.goGlobal(); model.clearFilters(); model.closePanel(); try await settle(model)
            window.setContentSize(NSSize(width: 960, height: 600)); try await settle(model)
            guard let compactSurface = find(StorageMapSurface.self, in: content), compactSurface.window === window else { throw UXVerificationError(message: "Current compact native storage map missing") }
            let compactBounds = compactSurface.bounds
            evidence["compactWindowGeometry"] = geometry(surface: compactSurface, content: content)
            evidence["compactUsableMapFraction"] = compactSurface.bounds.width * compactSurface.bounds.height / (content.safeAreaRect.width * content.safeAreaRect.height)
            try check("compactMapRemainsDominant", compactSurface.bounds.width * compactSurface.bounds.height >= content.safeAreaRect.width * content.safeAreaRect.height * 0.75)
            try capture(window, output.appendingPathComponent("compact.png"))
            model.showFolders = true; try await settle(model)
            try check("compactTreeDoesNotResizeMap", compactSurface.bounds == compactBounds)
            guard let compactOutline = find(NSOutlineView.self, in: content), let compactScroll = compactOutline.enclosingScrollView else { throw UXVerificationError(message: "Compact native folder outline missing") }
            let compactTreeFrame = compactScroll.convert(compactScroll.bounds, to: content)
            evidence["compactTreeFrame"] = NSStringFromRect(compactTreeFrame)
            try check("compactTreeFitsNativeContent", content.bounds.insetBy(dx: -1, dy: -1).contains(compactTreeFrame) && compactTreeFrame.width >= 300 && compactTreeFrame.height >= 200)
            try capture(window, output.appendingPathComponent("compact-folders.png"))
            let compactShares = parentShareGeometry(compactOutline)
            evidence["compactTreeParentShareGeometry"] = compactShares
            try check("compactTreeNumbersFitNativeViewport", !compactShares.isEmpty && compactShares.allSatisfy { $0["fitsHorizontally"] as? Bool == true })
            try check("finalWorkspaceHasNoQueryError", model.error == nil)
            model.closePanel(); window.setContentSize(NSSize(width: 1440, height: 900)); try await settle(model)
            evidence["result"] = "completed"
        } catch {
            evidence["result"] = "failed"; evidence["error"] = error.localizedDescription
        }
        evidence["recordedAt"] = ISO8601DateFormatter().string(from: Date()); save()
    }
    private static func waitUntil(_ test: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(180)
        while !test() {
            guard Date() < deadline else { throw UXVerificationError(message: "Timed out waiting for native state") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
    private static func settle(_ model: AppModel, composition: Bool = false) async throws {
        try await pause()
        try await waitUntil {
            model.loadingFolder == nil && !model.isQuerying && (!composition || !model.isLoadingComposition)
                && !NSApp.windows.compactMap(\.contentView).contains(where: { find(StorageMapSurface.self, in: $0)?.isResolvingMatches == true })
        }
        try await pause()
    }
    private static func pause() async throws { try await Task.sleep(for: .milliseconds(300)) }
    private static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews { if let match = find(type, in: child) { return match } }
        return nil
    }
    private static func key(_ code: UInt16, _ window: NSWindow, _ characters: String) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
    }
    private static func geometry(surface: StorageMapSurface, content: NSView) -> [String: String] {
        ["content": NSStringFromRect(content.bounds), "safeArea": NSStringFromRect(content.safeAreaRect),
         "map": NSStringFromRect(surface.convert(surface.bounds, to: content))]
    }
    /// Compare native numeric labels with their real scrolled viewport, including outline indentation.
    private static func parentShareGeometry(_ outline: NSOutlineView) -> [[String: Any]] {
        outline.layoutSubtreeIfNeeded()
        let visible = outline.visibleRect, rows = outline.rows(in: visible)
        guard rows.location != NSNotFound, rows.length > 0 else { return [] }
        var evidence: [[String: Any]] = []
        for row in rows.location..<min(rows.location + rows.length, outline.numberOfRows) {
            guard let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: true) else { continue }
            cell.layoutSubtreeIfNeeded()
            for field in descendants(NSTextField.self, in: cell) where field.stringValue.contains(" of parent") {
                let frame = field.convert(field.bounds, to: outline)
                let intrinsicWidth = field.intrinsicContentSize.width
                evidence.append(["row": row, "text": field.stringValue, "frame": NSStringFromRect(frame),
                    "viewport": NSStringFromRect(visible), "intrinsicWidth": intrinsicWidth,
                    "fitsHorizontally": frame.minX >= visible.minX - 1 && frame.maxX <= visible.maxX + 1
                        && (intrinsicWidth < 0 || intrinsicWidth <= field.bounds.width + 1)])
            }
        }
        return evidence
    }
    private static func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(type, in: $0) }
    }
    private static func capture(_ window: NSWindow, _ path: URL) throws {
        guard let content = window.contentView else { throw UXVerificationError(message: "Native content unavailable") }
        content.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { throw UXVerificationError(message: "Native bitmap unavailable") }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw UXVerificationError(message: "PNG unavailable") }
        try png.write(to: path)
    }
}
private struct UXVerificationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
