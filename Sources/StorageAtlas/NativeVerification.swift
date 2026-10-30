import AppKit
import Foundation
import StorageCore

/// Opt-in development checks of the actual running native window. No alternate UI or data.
@MainActor enum NativeVerification {
    private static var started = false
    static func runIfRequested(model: AppModel) async {
        let args = ProcessInfo.processInfo.arguments
        await NativeUXVerification.runIfRequested(model: model)
        guard !started, let flag = args.firstIndex(of: "--verify-ui"), args.indices.contains(flag + 1) else { return }
        started = true
        let output = URL(fileURLWithPath: args[flag + 1], isDirectory: true)
        var evidence: [String: Any] = [:]
        evidence["restoredCompletedAtLaunch"] = model.summary?.scopeKind == .global && model.summary?.status == "complete" && !model.isScanning
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try Data("{\"result\":\"running\"}".utf8).write(to: output.appendingPathComponent("native-verification.json"))
            let deadline = Date().addingTimeInterval(900)
            var capturedProgress = false
            while model.isScanning || model.isQuerying || model.summary == nil || model.mapNodes.isEmpty {
                if let error = model.error, !model.isScanning { throw VerificationFailure(message: error) }
                if !capturedProgress, model.summary?.scopeKind == .global, !model.mapNodes.isEmpty,
                   let window = NSApp.windows.first(where: { $0.contentView != nil && !($0 is NSPanel) }) {
                    window.setContentSize(NSSize(width: 1440, height: 900))
                    try await Task.sleep(for: .milliseconds(800))
                    try capture(window, output.appendingPathComponent("scanning.png"))
                    capturedProgress = true
                }
                guard Date() < deadline else { throw VerificationFailure(message: "Timed out waiting for a measured native map.") }
                try await Task.sleep(for: .milliseconds(500))
            }
            guard let window = NSApp.windows.first(where: { $0.contentView != nil && !($0 is NSPanel) }) else { throw VerificationFailure(message: "No native window.") }
            window.setContentSize(NSSize(width: 1440, height: 900))
            model.goGlobal(); model.showDetails = false; model.showItems = false
            try await settle(model)
            try capture(window, output.appendingPathComponent("global.png"))
            evidence["scope"] = model.summary?.scopeKind.rawValue
            evidence["status"] = model.summary?.status
            evidence["files"] = model.summary?.fileCount
            evidence["allocatedBytes"] = model.summary?.allocatedBytes
            evidence["coverageNotes"] = model.summary?.issueCount
            evidence["mapBytes"] = model.mapNodes.reduce(Int64(0)) { $0 + $1.bytes }
            evidence["mapMatchesSnapshot"] = model.mapNodes.reduce(Int64(0)) { $0 + $1.bytes } == model.summary?.allocatedBytes

            guard let content = window.contentView, let surface = findSurface(content) else { throw VerificationFailure(message: "Native drawing surface missing.") }
            let mapArea = surface.bounds.width * surface.bounds.height
            let usable = content.safeAreaRect
            evidence["mapAreaFractionOfWindow"] = mapArea / (content.bounds.width * content.bounds.height)
            evidence["mapAreaFraction"] = mapArea / (usable.width * usable.height)
            evidence["windowContentSize"] = [Double(content.bounds.width), Double(content.bounds.height)]
            evidence["usableContentSize"] = [Double(usable.width), Double(usable.height)]
            evidence["mapSize"] = [Double(surface.bounds.width), Double(surface.bounds.height)]
            let boundsBefore = surface.bounds
            let layout = TreemapLayout.layout(nodes: model.mapNodes, in: surface.bounds)
            if let tile = layout.tiles.first(where: { $0.node.entry != nil && !$0.node.isRollup && $0.rect.width > 40 && $0.rect.height > 40 }) {
                let location = surface.convert(NSPoint(x: tile.rect.midX, y: tile.rect.midY), to: nil)
                if let event = mouse(.mouseMoved, location, window, count: 0) { surface.mouseMoved(with: event) }
                evidence["nativeHover"] = model.hoveredNode?.id == tile.node.id
                if let event = mouse(.leftMouseDown, location, window, count: 1) { surface.mouseDown(with: event) }
                try await settle(model)
                evidence["nativeSelect"] = model.selected?.path == tile.node.path && model.showDetails
                evidence["drawerKeepsMapGeometry"] = surface.bounds == boundsBefore
                try capture(window, output.appendingPathComponent("details.png"))
                if let key = key(53, window) { surface.keyDown(with: key) }
                try await settle(model)
                evidence["nativeEscapeClosesDrawer"] = !model.showDetails && !model.showItems
            }

            if let tile = layout.tiles.first(where: { $0.node.isDirectory && !$0.node.isRollup && $0.rect.width > 40 && $0.rect.height > 40 }) {
                let location = surface.convert(NSPoint(x: tile.rect.midX, y: tile.rect.midY), to: nil)
                if let event = mouse(.leftMouseDown, location, window, count: 2) { surface.mouseDown(with: event) }
                try await settle(model)
                evidence["nativeDoubleClickZoom"] = model.currentFolder == tile.node.path
                try capture(window, output.appendingPathComponent("zoom.png"))
                if let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 115) {
                    surface.keyDown(with: key)
                }
                try await settle(model)
                evidence["nativeHomeKey"] = model.currentFolder == model.summary?.root
            }

            model.showItems = true
            try await settle(model)
            try capture(window, output.appendingPathComponent("largest-files.png"))
            if let table = findTable(content), table.numberOfRows > 1 {
                window.makeFirstResponder(table)
                table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                if let down = key(125, window, characters: "\u{F701}") { table.keyDown(with: down) }
                try await settle(model)
                evidence["nativeListArrowSelection"] = table.selectedRow > 0 && model.selected != nil
            }
            if let rollup = layout.tiles.first(where: { $0.node.isRollup && $0.rect.width > 10 && $0.rect.height > 10 }) {
                model.showItems = false
                let location = surface.convert(NSPoint(x: rollup.rect.midX, y: rollup.rect.midY), to: nil)
                if let event = mouse(.leftMouseDown, location, window, count: 1) { surface.mouseDown(with: event) }
                try await settle(model)
                evidence["nativeRollupOpensScopedList"] = model.showItems && model.listScopeLabel == shortPath(rollup.node.path)
                evidence["rollupRowsWithinParent"] = model.listEntries.allSatisfy { rollup.node.path == "/" || $0.path.hasPrefix(rollup.node.path + "/") }
                if model.listHasMore {
                    let oldCount = model.listEntries.count
                    model.loadMoreFiles(); try await settle(model)
                    evidence["rollupLoadMore"] = model.listEntries.count > oldCount
                }
                try capture(window, output.appendingPathComponent("rollup-files.png"))
            }
            model.goGlobal()
            try await settle(model)
            if let hidden = model.listEntries.first(where: { entry in !layout.tiles.contains(where: { $0.node.path == entry.path }) }) {
                let partition = model.mapNodes
                model.showItems = true; model.search = hidden.path; model.reload()
                try await settle(model)
                evidence["positiveSearchFindsOutsideFrontier"] = model.listEntries.contains(where: { $0.path == hidden.path })
                evidence["searchKeepsPartition"] = model.mapNodes == partition
                try capture(window, output.appendingPathComponent("search.png"))
            }
            model.showItems = true; model.search = "__atlas_verification_no_such_filename__"; model.reload()
            try await settle(model)
            evidence["emptySearch"] = model.listEntries.isEmpty
            try capture(window, output.appendingPathComponent("search-empty.png"))
            model.search = ""; model.category = .development; model.reload()
            try await settle(model)
            evidence["categoryQuery"] = !model.listEntries.isEmpty && model.listEntries.allSatisfy { $0.category == .development }
            evidence["searchKeepsMapGeometry"] = surface.bounds == boundsBefore
            try capture(window, output.appendingPathComponent("development.png"))
            model.category = nil; model.showItems = false; model.reload()
            try await settle(model)

            window.setContentSize(NSSize(width: 960, height: 600))
            try await settle(model)
            try capture(window, output.appendingPathComponent("compact.png"))
            if let entry = model.listEntries.first { model.select(entry) }
            try await settle(model)
            try capture(window, output.appendingPathComponent("compact-details.png"))
            model.dismissTransient()
            window.setContentSize(NSSize(width: 1440, height: 900))
            try await settle(model)
            model.showCoverage = true
            try await settle(model)
            if let coverage = NSApp.windows.first(where: { $0 !== window && $0.isVisible && $0.contentView != nil }) {
                try capture(coverage, output.appendingPathComponent("coverage.png"))
                evidence["nativeCoveragePopover"] = true
            }
            model.showCoverage = false
            try await settle(model)
            evidence["result"] = "completed"
        } catch {
            evidence["result"] = "failed"
            evidence["error"] = error.localizedDescription
        }
        evidence["recordedAt"] = ISO8601DateFormatter().string(from: Date())
        if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output.appendingPathComponent("native-verification.json"))
        }
    }

    private static func settle(_ model: AppModel) async throws {
        try await Task.sleep(for: .milliseconds(350))
        let deadline = Date().addingTimeInterval(180)
        while model.isQuerying || NSApp.windows.compactMap(\.contentView).contains(where: { findSurface($0)?.isResolvingMatches == true }) {
            guard Date() < deadline else { throw VerificationFailure(message: "Timed out waiting for native query/highlight work.") }
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(650))
    }
    private static func mouse(_ type: NSEvent.EventType, _ point: NSPoint, _ window: NSWindow, count: Int) -> NSEvent? {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: count, pressure: 1)
    }
    private static func key(_ code: UInt16, _ window: NSWindow, characters: String = "") -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
    }
    private static func findTable(_ view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for child in view.subviews { if let result = findTable(child) { return result } }
        return nil
    }
    private static func findSurface(_ view: NSView) -> StorageMapSurface? {
        if let surface = view as? StorageMapSurface { return surface }
        for child in view.subviews { if let result = findSurface(child) { return result } }
        return nil
    }
    private static func capture(_ window: NSWindow, _ url: URL) throws {
        guard let view = window.contentView else { throw VerificationFailure(message: "Window has no content view.") }
        view.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw VerificationFailure(message: "Native bitmap unavailable.") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw VerificationFailure(message: "Native PNG encoding failed.") }
        try data.write(to: url)
    }
}

private struct VerificationFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
