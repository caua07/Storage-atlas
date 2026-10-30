import AppKit
import SwiftUI
import StorageCore

/// A continuous measured field beneath optional floating instruments.
struct WorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @FocusState private var searchFocused: Bool
    private var reduceMotion: Bool { systemReduceMotion || MapStyle.reduceMotion }
    private var measuredBytes: Int64 { model.mapNodes.reduce(0) { $0 + $1.bytes } }
    private var measurementLabel: String {
        if !model.mapNodes.isEmpty { return byteString(measuredBytes) }
        if focusedAccessIssue != nil { return "Unknown size" }
        if model.loadingFolder == nil, !model.isLoadingComposition, !model.isQuerying, let composition = model.composition {
            return byteString(composition.allocatedBytes)
        }
        return "—"
    }

    var body: some View {
        ZStack {
            MapStyle.canvas
            map.padding(.horizontal, 12).padding(.top, 72).padding(.bottom, 44)
            VStack(spacing: 0) {
                transport.padding(.horizontal, 12).padding(.top, 8)
                if !model.isScanning, model.showReadAccessNotice, model.error == nil {
                    coverageNotice.padding(.top, 10).padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                statusShelf.padding(.horizontal, 12).padding(.bottom, 6)
            }
            if model.panel != nil {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    MapInspectorView().frame(width: 360)
                        .background(MapStyle.panel)
                        .clipShape(RoundedRectangle(cornerRadius: MapStyle.floatingRadius, style: .continuous))
                        .shadow(color: .black.opacity(0.32), radius: 24, x: 0, y: 10)
                        .accessibilityIdentifier("atlas.inspector")
                }.padding(.top, 80).padding(.bottom, 52).padding(.trailing, 20)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
            if let error = model.error {
                VStack {
                    errorNotice(error).frame(maxWidth: 480)
                    Spacer()
                }.padding(.top, 82).padding(.leading, 24).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let hovered = model.hoveredNode, model.panel == nil, model.error == nil {
                VStack { Spacer(); hoverReadout(hovered) }
                    .padding(.leading, 24).padding(.bottom, 62)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false).transition(.opacity)
            }
        }
        .background(MapStyle.canvas).foregroundStyle(MapStyle.text).font(.system(size: 12))
        .clipped()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.panel)
        .task(id: model.search) {
            try? await Task.sleep(for: .milliseconds(180))
            if !Task.isCancelled { model.reload() }
        }
        .onChange(of: model.category) { _, _ in model.reload() }
        .onChange(of: model.searchScope) { _, _ in model.reload() }
        .onChange(of: model.searchFocusRequest) { _, _ in searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.checkReadAccess() }
        .onExitCommand { model.dismissTransient() }
        .popover(isPresented: $model.showCoverage, arrowEdge: .bottom) { MapCoverageView() }
    }

    private var transport: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                AtlasMark()
                Text("Atlas").font(.system(size: 16, weight: .semibold)).tracking(-0.3)
            }.padding(.leading, 5).accessibilityLabel("Storage Atlas")
            Rectangle().fill(MapStyle.line).frame(width: 1, height: 26)
            HStack(spacing: 0) {
                Button(action: model.goBack) { Image(systemName: "chevron.left").frame(width: 10) }
                    .disabled(!model.canGoBack).help("Back (⌘[)").accessibilityLabel("Back")
                Button(action: model.goForward) { Image(systemName: "chevron.right").frame(width: 10) }
                    .disabled(!model.canGoForward).help("Forward (⌘])").accessibilityLabel("Forward")
                Button(action: model.goUp) { Image(systemName: "arrow.up").frame(width: 10) }
                    .disabled(model.currentFolder == nil || model.currentFolder == model.summary?.root)
                    .help("Enclosing folder (Backspace)").accessibilityLabel("Enclosing folder")
            }.buttonStyle(AtlasControlStyle())
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    breadcrumbLine(compact: false)
                    breadcrumbLine(compact: true)
                    pathMenu
                }
                HStack(spacing: 5) {
                    Text(model.summary?.scopeKind == .folder ? "Folder snapshot" : "Mapped").foregroundStyle(MapStyle.secondary).lineLimit(1)
                    Text(measurementLabel).monospacedDigit().fontWeight(.medium)
                    if model.loadingFolder != nil { ProgressView().controlSize(.mini) }
                }.font(.system(size: 11))
                    .help("Measured allocated bytes in the displayed map. Logical size and volume capacity are separate.")
            }.frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
            searchField
            HStack(spacing: 3) {
                Button { model.togglePanel(.folders) } label: { Label("Folders", systemImage: "folder") }
                    .buttonStyle(AtlasControlStyle(active: model.showFolders))
                    .help("Folder tree (⌘\\)").accessibilityLabel("Toggle folder tree")
                Button { model.togglePanel(.results) } label: { Image(systemName: "list.bullet").frame(width: 16) }
                    .buttonStyle(AtlasControlStyle(active: model.showItems))
                    .help("Largest files and search results (⌘L)").accessibilityLabel("Toggle items list")
                Button { model.togglePanel(.details) } label: { Image(systemName: "sidebar.right").frame(width: 16) }
                    .buttonStyle(AtlasControlStyle(active: model.showDetails))
                    .help("Item details (⌘I)").accessibilityLabel("Toggle item details")
                if model.isScanning {
                    Button(action: model.cancelScan) { Image(systemName: "stop.circle").frame(width: 16) }
                        .disabled(model.isCancelling).help(model.isCancelling ? "Waiting for filesystem operation" : "Stop scan")
                        .accessibilityLabel(model.isCancelling ? "Cancellation requested" : "Stop scan")
                        .buttonStyle(AtlasControlStyle())
                } else {
                    Button(action: model.refreshGlobal) { Image(systemName: "arrow.clockwise").frame(width: 16) }
                        .help("Refresh global scan (⌘R)").accessibilityLabel("Refresh global scan")
                        .buttonStyle(AtlasControlStyle())
                }
            }
        }.padding(.horizontal, 10).frame(height: 56)
            .modifier(AtlasFloatingSurface(radius: 16))
            .accessibilityIdentifier("atlas.toolbar")
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(MapStyle.secondary)
            Menu {
                Button("This folder") { model.searchScope = .folder }
                Button(model.summary?.scopeKind == .global ? "Mac snapshot" : "Scan snapshot") { model.searchScope = .global }
            } label: {
                Text(model.searchScope == .global || model.currentFolder == model.summary?.root ? (model.summary?.scopeKind == .global ? "Mac" : "Scan") : "Folder")
                    .font(.system(size: 11)).foregroundStyle(MapStyle.secondary)
            }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Search scope")
            TextField("Search paths", text: $model.search).textFieldStyle(.plain)
                .font(.system(size: 12)).focused($searchFocused).onSubmit { model.panel = .results }
                .accessibilityLabel("Search indexed paths").accessibilityIdentifier("atlas.search")
            if model.isQuerying { ProgressView().controlSize(.mini).help("Reading index…") }
            if !model.search.isEmpty {
                Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(MapStyle.secondary).accessibilityLabel("Clear search")
            }
        }.padding(.horizontal, 11).frame(width: 208, height: 34)
            .background(MapStyle.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func breadcrumbLine(compact: Bool) -> some View {
        HStack(spacing: 6) {
            let crumbs = model.breadcrumbs
            if compact, crumbs.count > 2 {
                pathMenu
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(MapStyle.muted)
                if let last = crumbs.last {
                    Button(last.name) { model.navigate(last.path) }.lineLimit(1).truncationMode(.middle)
                        .help(last.path).accessibilityLabel("Open \(last.path)")
                }
            } else {
                ForEach(crumbs, id: \.path) { crumb in
                    if crumb.path != crumbs.first?.path {
                        Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(MapStyle.muted)
                    }
                    Button(crumb.name) { model.navigate(crumb.path) }.fixedSize()
                        .help(crumb.path).accessibilityLabel("Open \(crumb.path)")
                }
            }
        }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).lineLimit(1)
    }

    private var pathMenu: some View {
        Menu {
            ForEach(model.breadcrumbs, id: \.path) { crumb in
                Button(shortPath(crumb.path)) { model.navigate(crumb.path) }
            }
        } label: { Text(model.breadcrumbs.count > 1 ? "…" : model.breadcrumbs.first?.name ?? "Mac") }
            .menuStyle(.borderlessButton).font(.system(size: 12, weight: .medium)).fixedSize()
            .accessibilityLabel("Path ancestors")
    }

    private var statusShelf: some View {
        HStack(spacing: 12) {
            if model.isScanning {
                scanActivity
            } else {
                Button { model.showCoverage = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model.summary?.isPartial == true ? (model.summary?.traversalCompleted == true ? "exclamationmark.circle" : "circle.lefthalf.filled") : "checkmark.circle")
                            .foregroundStyle(model.summary?.isPartial == true ? MapStyle.warning : MapStyle.secondary)
                        Text(model.statusLabel)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }.buttonStyle(.plain).help("Scope, access gaps and measurement limits").accessibilityLabel("Coverage: \(model.statusLabel)")
                if let scan = model.summary {
                    Text((scan.finished ?? scan.started).formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(MapStyle.muted).lineLimit(1).layoutPriority(-1)
                        .help((scan.finished ?? scan.started).formatted(date: .complete, time: .shortened))
                }
            }
            Spacer(minLength: 8)
            if model.isScanning {
                categoryMenu
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) { categoryKey; categoryMenu }
                    categoryMenu
                }
            }
            Spacer(minLength: 8)
            if let capacity = model.capacity {
                Button { model.showCoverage = true } label: {
                    Text("\(byteString(capacity.used)) used / \(byteString(capacity.total)) · \(byteString(capacity.free)) free")
                        .monospacedDigit()
                }.buttonStyle(.plain).fixedSize()
                    .help("Whole-volume used, total and free space. The map only contains measured file allocation; click for the difference and coverage notes.")
                    .accessibilityLabel("Volume: \(byteString(capacity.used)) used, \(byteString(capacity.total)) total, \(byteString(capacity.free)) free. Show coverage.")
            }
        }.font(.system(size: 11)).foregroundStyle(MapStyle.secondary)
            .padding(.horizontal, 13).frame(height: 32)
            .modifier(AtlasFloatingSurface(radius: 12))
            .accessibilityIdentifier("atlas.statusShelf")
    }

    private var scanActivity: some View {
        HStack(spacing: 10) {
            Button { model.showCoverage = true } label: {
                Text(model.scanActivityLabel)
                    .foregroundStyle(model.isCancelling ? MapStyle.warning : MapStyle.text)
            }.buttonStyle(.plain).fixedSize()
                .help("Scan coverage and measurement limits")
                .accessibilityLabel("Coverage: \(model.statusLabel)")
            ScanActivityBar(paused: reduceMotion || model.isCancelling, stopping: model.isCancelling)
                .frame(width: 112, height: 6)
            if let progress = model.progress {
                Text("\(progress.fileCount.formatted()) files · \(byteString(progress.allocatedBytes)) scanned")
                    .monospacedDigit().lineLimit(1)
            } else {
                Text("Counting files…").lineLimit(1)
            }
        }
        .layoutPriority(1)
        .help("\(model.scanActivityHelp)\n\(model.progress?.currentPath ?? "Preparing the scan")")
        .accessibilityIdentifier("atlas.scanActivity")
    }

    private var categoryMenu: some View {
        Menu {
            Button("All categories") { model.category = nil }
            Divider()
            ForEach(StorageCategory.allCases) { category in
                Button { model.category = model.category == category ? nil : category } label: {
                    Label(categorySummary(category), systemImage: model.category == category ? "checkmark" : category.symbol)
                }.disabled(category == .models && model.composition?.classificationVersion == 1)
            }
            if model.isLoadingComposition { Text("Calculating composition…") }
            else if let composition = model.composition, composition.classificationVersion < 2 {
                Divider(); Text("Legacy classification · refresh to separate model weights")
            }
        } label: {
            HStack(spacing: 5) {
                if let category = model.category { Circle().fill(MapStyle.color(category)).frame(width: 6, height: 6) }
                Text(model.category?.title ?? "Categories")
            }
        }.menuStyle(.borderlessButton).fixedSize().help("Composition of this folder; highlights preserve map areas")
    }

    private var categoryKey: some View {
        HStack(spacing: 3) {
            ForEach(StorageCategory.allCases) { category in
                Button { model.category = model.category == category ? nil : category } label: {
                    HStack(spacing: 4) {
                        Circle().fill(MapStyle.color(category)).frame(width: 6, height: 6)
                        Text(keyLabel(category))
                    }.padding(.horizontal, 6).padding(.vertical, 5)
                        .background(model.category == category ? MapStyle.field : .clear, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).help(categorySummary(category))
                    .accessibilityLabel("Highlight \(categorySummary(category))")
                    .disabled(category == .models && model.composition?.classificationVersion == 1)
            }
        }.font(.system(size: 11)).fixedSize()
    }

    private func categorySummary(_ category: StorageCategory) -> String {
        guard let composition = model.composition else { return category.title }
        if category == .models && composition.classificationVersion < 2 { return category.title + " · refresh required for legacy snapshot" }
        let bytes = composition.totals.first(where: { $0.category == category })?.bytes ?? 0
        let share = composition.allocatedBytes > 0 ? " · " + (Double(bytes) / Double(composition.allocatedBytes)).formatted(.percent.precision(.fractionLength(1))) : ""
        return category.title + " · " + byteString(bytes) + share
    }
    private func keyLabel(_ category: StorageCategory) -> String {
        switch category {
        case .development: "Dev"
        case .applications: "Apps"
        case .caches: "Caches"
        case .archives: "Archives"
        case .media: "Media"
        case .models: "Models"
        case .documents: "Docs"
        case .other: "Other"
        }
    }

    @ViewBuilder private var map: some View {
        if !model.mapNodes.isEmpty {
            TreemapCanvasView(nodes: model.mapNodes, selectedPath: model.selected?.path,
                              matchingPaths: model.matchingPaths, search: model.search, category: model.category,
                              onHover: { model.hoveredNode = $0; model.hoveredPath = $0?.path },
                              onSelect: { node in
                                  if let entry = node.entry { model.select(entry) }
                                  else if !node.isRollup { model.selectPath(node.path) }
                                  else { model.inspectRollup(node) }
                              },
                              onZoom: { if $0.isRollup { model.inspectRollup($0) } else if $0.isDirectory { model.navigate($0.path) } },
                              onReveal: { if let entry = $0.entry { model.reveal(entry) } },
                              onCopy: { if let entry = $0.entry { model.copyPath(entry) } },
                              onUp: model.goUp, onGlobal: model.goGlobal, onDismiss: model.dismissTransient)
                .accessibilityLabel("Storage map. Open Folders for tree navigation; select a folder and choose Open contents.")
                .overlay(alignment: .topLeading) {
                    if let path = model.loadingFolder {
                        HStack(spacing: 8) { ProgressView().controlSize(.mini); Text("Opening \(shortPath(path))…").lineLimit(1).truncationMode(.middle) }
                            .font(.system(size: 12)).padding(12).modifier(AtlasFloatingSurface(radius: 12)).padding(12).allowsHitTesting(false)
                    }
                }
        } else { emptyState }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: focusedAccessIssue != nil ? "folder.badge.questionmark" : "square.stack.3d.up")
                .font(.system(size: 26, weight: .light)).foregroundStyle(MapStyle.secondary)
            if model.isScanning || model.isQuerying { ProgressView().controlSize(.small) }
            Text(model.isScanning ? "Scanning storage…" : model.isQuerying ? "Reading index…" : focusedAccessIssue != nil ? "Size unknown · access unavailable" : "No measured files in this view")
                .font(.system(size: 16, weight: .medium))
            if let progress = model.progress, model.isScanning {
                Text("\(progress.fileCount.formatted()) files · \(byteString(progress.allocatedBytes)) measured").foregroundStyle(MapStyle.secondary)
                Text(shortPath(progress.currentPath)).foregroundStyle(MapStyle.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 480)
            } else if let issue = focusedAccessIssue {
                Text(issue.message).foregroundStyle(MapStyle.secondary).lineLimit(3).frame(maxWidth: 480)
                Button("Coverage") { model.showCoverage = true }.buttonStyle(AtlasControlStyle())
            } else if !model.isScanning && !model.isQuerying {
                Button("Refresh global scan", action: model.refreshGlobal).buttonStyle(AtlasControlStyle())
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var focusedAccessIssue: ScanIssue? { model.issues.first { $0.path == model.currentFolder } }
    private var coverageNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: "externaldrive.badge.exclamationmark").foregroundStyle(MapStyle.warning)
                    .accessibilityHidden(true)
                Text("Allow Atlas to read your storage").font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 12)
                Button(action: model.dismissReadAccessNotice) {
                    Image(systemName: "xmark").frame(width: 20, height: 20)
                }.buttonStyle(AtlasControlStyle())
                    .accessibilityLabel("Dismiss coverage notice; coverage remains available in the status bar")
            }
            Text("Read access is blocked for a protected folder. Full Disk Access can improve the map. If already enabled, reopen Atlas and check again. Atlas only reads file information and sizes; it never changes or deletes files.")
                .foregroundStyle(MapStyle.secondary).fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
            Button { model.showCoverage = true } label: {
                HStack(spacing: 8) {
                    Text("Set up access")
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
                }
            }.buttonStyle(AtlasNoticeActionStyle())
                .help("Open the guide to enable Full Disk Access in macOS Settings")
        }.font(.system(size: 12)).padding(18).frame(maxWidth: 510, alignment: .leading)
            .modifier(AtlasFloatingSurface(radius: 14))
            .accessibilityIdentifier("atlas.coverageNotice")
    }
    private func hoverReadout(_ node: TreemapNode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: node.isRollup ? "square.stack" : node.isDirectory ? "folder" : "doc")
                .font(.system(size: 17, weight: .light)).foregroundStyle(MapStyle.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(node.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(shortPath(node.path)).font(.system(size: 11)).foregroundStyle(MapStyle.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Text(byteString(node.bytes)).font(.system(size: 15, weight: .medium)).monospacedDigit().fixedSize()
        }.padding(14).frame(maxWidth: 480).modifier(AtlasFloatingSurface(radius: 14))
    }
    private func errorNotice(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(MapStyle.warning)
            Text(error).font(.system(size: 12)).textSelection(.enabled)
            Spacer(minLength: 4)
            Button { model.error = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Dismiss error")
        }.padding(14).modifier(AtlasFloatingSurface(radius: 14))
    }
}
