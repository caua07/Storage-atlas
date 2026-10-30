import AppKit
import SwiftUI
import StorageCore

struct MapInspectorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedListPath: String?
    @State private var showEvidence = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    panelTab("Folders", panel: .folders)
                    panelTab("Results", panel: .results)
                    panelTab("Details", panel: .details)
                }
                Spacer(minLength: 0)
                Button(action: model.closePanel) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(InspectorButtonStyle(compact: true))
                .help("Close panel (Escape)").accessibilityLabel("Close panel")
            }
            .padding(.horizontal, 12).frame(height: 54)
            Rectangle().fill(MapStyle.line.opacity(0.6)).frame(height: 1)
            if model.showFolders { FolderTreeView() }
            else if model.showItems { items }
            else if let entry = model.selected { details(entry) }
            else {
                InspectorEmptyState(symbol: "cursorarrow", title: "Select an item",
                                    message: "Choose a tile or a file to inspect its path and measurements.")
            }
        }
        .foregroundStyle(MapStyle.text).font(.system(size: 12))
        .onChange(of: model.selected?.path) { _, _ in showEvidence = false }
    }

    private func panelTab(_ title: String, panel: WorkspacePanel) -> some View {
        let active = (model.panel ?? .details) == panel
        return Button { if !active { model.togglePanel(panel) } } label: {
            Text(title).font(.system(size: 12, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? MapStyle.text : MapStyle.secondary)
                .padding(.horizontal, 12).frame(height: 30)
                .background(active ? MapStyle.field : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(InspectorButtonStyle(compact: true))
        .accessibilityValue(active ? "Selected" : "")
    }

    private var items: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.listScopeLabel).font(.system(size: 12, weight: .medium))
                    .lineLimit(2).truncationMode(.middle)
                if let container = model.selectedContainerPath {
                    Label("Contained in \(shortPath(container))", systemImage: "square.stack")
                        .font(.system(size: 11)).foregroundStyle(MapStyle.secondary)
                        .lineLimit(2).truncationMode(.middle)
                }
                HStack {
                    Text("\(model.listEntries.count.formatted()) shown")
                    Spacer()
                    if model.isQuerying {
                        ProgressView().controlSize(.mini).scaleEffect(0.8)
                        Text("Reading index…")
                    } else { Text("On disk") }
                }.font(.system(size: 11)).foregroundStyle(MapStyle.secondary)
            }.padding(16)
            if model.listEntries.isEmpty {
                VStack(spacing: 0) {
                    InspectorEmptyState(symbol: model.isQuerying ? "hourglass" : "magnifyingglass",
                                        title: model.isQuerying ? "Reading index…" : "No matching items",
                                        message: model.isQuerying ? "Results will appear in this scope." : "No indexed items match the current scope and filters.")
                    if !model.search.isEmpty || model.category != nil {
                        Button("Clear filters", action: model.clearFilters)
                            .buttonStyle(InspectorButtonStyle()).padding(.bottom, 10)
                    }
                    if model.searchScope == .folder && model.currentFolder != model.summary?.root {
                        Button("Search Mac snapshot") { model.searchScope = .global; model.reload() }
                            .buttonStyle(InspectorButtonStyle()).padding(.bottom, 20)
                    }
                }.frame(maxHeight: .infinity, alignment: .top)
            } else {
                List(selection: $selectedListPath) {
                    ForEach(model.listEntries) { entry in
                        resultRow(entry).tag(entry.path).id(entry.path)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowBackground(selectedListPath == entry.path ? MapStyle.field : Color.clear)
                            .accessibilityLabel("\(entry.name), \(entry.isDirectory ? "folder" : "file"), \(resultAllocatedLabel(entry)) on disk, \(entry.path)")
                            .contextMenu {
                                if entry.isDirectory { Button("Open contents") { model.activateTreeEntry(entry) } }
                                Button("Inspect") { model.inspect(entry) }
                                Divider()
                                Button("Open containing folder") { model.openContainingFolder(entry) }
                                Button("Reveal in Finder") { model.reveal(entry) }
                                Button("Copy path") { model.copyPath(entry) }
                            }
                            .onTapGesture(count: 2) { model.inspect(entry) }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden).tint(MapStyle.secondary)
                .background(ListPositionObserver(entries: model.listEntries, position: model.listScrollPath,
                                                 onPosition: model.rememberListPosition))
                .onChange(of: selectedListPath) { _, path in
                    if let entry = model.listEntries.first(where: { $0.path == path }) { model.selectTreeEntry(entry) }
                }
                .onChange(of: model.selected?.path) { _, path in
                    selectedListPath = model.listEntries.contains(where: { $0.path == path }) ? path : nil
                }
                .onAppear { selectedListPath = model.selected?.path }
                Rectangle().fill(MapStyle.line.opacity(0.6)).frame(height: 1)
                VStack(spacing: 10) {
                    HStack {
                        if model.listHasMore && !model.isQuerying {
                            Button("Load more", action: model.loadMoreFiles).buttonStyle(InspectorButtonStyle(compact: true))
                        } else {
                            Text(model.isQuerying ? "Reading index…" : "All matching files shown")
                                .font(.system(size: 11)).foregroundStyle(MapStyle.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        Button("Open folder") {
                            if let entry = model.selected { model.openContainingFolder(entry) }
                        }.disabled(model.selected == nil)
                        Button("Inspect") {
                            if let entry = model.selected { model.inspect(entry) }
                        }.disabled(model.selected == nil).keyboardShortcut(.return, modifiers: [])
                        Spacer(minLength: 0)
                    }.buttonStyle(InspectorButtonStyle())
                }.padding(14)
            }
        }
    }

    private func resultRow(_ entry: StorageEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isSymbolicLink ? "link" : entry.isDirectory ? "folder" : entry.category.symbol)
                .font(.system(size: 14)).foregroundStyle(entry.isDirectory ? MapStyle.secondary : MapStyle.color(entry.category))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name).font(.system(size: 12, weight: .medium)).foregroundStyle(MapStyle.text)
                    .lineLimit(1).truncationMode(.middle)
                Text(shortPath(entry.parent)).font(.system(size: 11)).foregroundStyle(MapStyle.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(resultAllocatedLabel(entry)).font(.system(size: 12, weight: .medium)).monospacedDigit()
                .foregroundStyle(MapStyle.text).fixedSize()
        }.frame(minHeight: 44).contentShape(Rectangle())
    }

    private func resultAllocatedLabel(_ entry: StorageEntry) -> String {
        let directGap = (model.issues + model.treeIssues).contains { $0.path == entry.path }
        return directGap && entry.allocatedBytes == 0 ? "Unknown size" : byteString(entry.allocatedBytes)
    }

    private func details(_ entry: StorageEntry) -> some View {
        let directGap = (model.issues + model.treeIssues).contains { $0.path == entry.path }
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: entry.isSymbolicLink ? "link" : entry.isDirectory ? "folder" : entry.category.symbol)
                            .foregroundStyle(entry.isDirectory ? MapStyle.secondary : MapStyle.color(entry.category))
                        Text(entry.isSymbolicLink ? "Symbolic link" : entry.isDirectory ? "Folder" : "File")
                        Text("·")
                        Text(entry.isDirectory ? folderNature : entry.category.title).lineLimit(2)
                    }.font(.system(size: 11)).foregroundStyle(MapStyle.secondary)
                    Text(entry.name).font(.system(size: 22, weight: .semibold)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(MapStyle.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                    if let container = model.selectedContainerPath {
                        Label("Contained in \(shortPath(container))", systemImage: "square.stack")
                            .font(.system(size: 11)).foregroundStyle(MapStyle.secondary).textSelection(.enabled)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(directGap && entry.allocatedBytes == 0 ? "Unknown size" : byteString(entry.allocatedBytes))
                        .font(.system(size: 30, weight: .medium)).monospacedDigit()
                    Text("Allocated on disk").font(.system(size: 11)).foregroundStyle(MapStyle.secondary)
                    if directGap {
                        Label("Access incomplete · measured content only", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11)).foregroundStyle(MapStyle.warning).padding(.top, 6)
                    }
                }
                VStack(spacing: 12) {
                    datum("Logical size", directGap && entry.logicalBytes == 0 ? "Unknown size" : byteString(entry.logicalBytes))
                    if entry.isDirectory { datum("Files inside", entry.fileCount.formatted()) }
                    if let scan = model.summary {
                        datum("Measured", (scan.finished ?? scan.started).formatted(date: .abbreviated, time: .shortened))
                    }
                    if let modified = entry.modified { datum("Modified", modified.formatted(date: .abbreviated, time: .omitted)) }
                }
                if entry.isDirectory {
                    if let composition = model.selectedComposition {
                        CategoryCompositionView(composition: composition)
                    } else {
                        Text("Composition not calculated").font(.system(size: 11)).foregroundStyle(MapStyle.secondary)
                    }
                }
                Rectangle().fill(MapStyle.line.opacity(0.7)).frame(height: 1)
                VStack(alignment: .leading, spacing: 12) {
                    if let rule = entry.rule {
                        Text(rule.title).font(.system(size: 13, weight: .semibold))
                        Text(rule.explanation).foregroundStyle(MapStyle.secondary)
                        Text(rule.consequence).foregroundStyle(MapStyle.secondary)
                        DisclosureGroup("Recognition evidence", isExpanded: $showEvidence) {
                            Text(rule.evidence).foregroundStyle(MapStyle.secondary).padding(.top, 8).textSelection(.enabled)
                        }.tint(MapStyle.secondary)
                    } else if entry.isSymbolicLink {
                        Text("A pointer to another location. Its target was not followed or counted through this path.").foregroundStyle(MapStyle.secondary)
                    } else {
                        Text(entry.isDirectory
                             ? "This folder includes measured descendants. Open its contents to compare what is inside."
                             : entry.category == .other
                             ? "No specific artifact rule matched this file. Ownership and whether it can be recreated are unknown."
                             : "Classified by filename extension. Ownership and whether it can be recreated are unknown.")
                            .foregroundStyle(MapStyle.secondary)
                    }
                }.font(.system(size: 12)).lineSpacing(3)
                VStack(alignment: .leading, spacing: 10) {
                    if entry.isDirectory {
                        Button { model.navigate(entry.path) } label: {
                            HStack { Text("Open contents"); Spacer(); Image(systemName: "arrow.right") }
                        }.buttonStyle(InspectorButtonStyle()).keyboardShortcut(.return, modifiers: [])
                    }
                    HStack(spacing: 8) {
                        Button("Reveal in Finder") { model.reveal(entry) }
                        Button("Copy path") { model.copyPath(entry) }
                    }.buttonStyle(InspectorButtonStyle())
                    Text("Allocated size does not measure exclusive recoverable space.")
                        .font(.system(size: 11)).foregroundStyle(MapStyle.secondary).lineSpacing(2).padding(.top, 2)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var folderNature: String {
        guard let composition = model.selectedComposition else { return "Composition not calculated" }
        if composition.isMixed { return "Mixed contents" }
        return composition.totals.first(where: { $0.count > 0 })?.category.title ?? "No measured files"
    }

    private func datum(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(MapStyle.secondary)
            Spacer(minLength: 0)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }.font(.system(size: 11))
    }
}

private struct CategoryCompositionView: View {
    let composition: ScopeComposition
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Contents by category").font(.system(size: 13, weight: .semibold))
            ForEach(composition.totals) { total in
                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(MapStyle.color(total.category)).frame(width: 6, height: 6)
                        Text(total.category.title).lineLimit(2)
                        Spacer(minLength: 0)
                        Text(byteString(total.bytes)).monospacedDigit().fixedSize()
                    }.font(.system(size: 11))
                    if composition.allocatedBytes > 0 {
                        let ratio = Double(total.bytes) / Double(composition.allocatedBytes)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(MapStyle.field)
                                Capsule().fill(MapStyle.color(total.category))
                                    .frame(width: geometry.size.width * max(0, min(1, ratio)))
                            }
                        }.frame(height: 3).accessibilityHidden(true)
                        Text(ratio.formatted(.percent.precision(.fractionLength(1))) + " of this folder")
                            .font(.system(size: 11)).foregroundStyle(MapStyle.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            if composition.totals.isEmpty {
                Text("No measured regular files.").font(.system(size: 11)).foregroundStyle(MapStyle.secondary)
            }
            if composition.classificationVersion < 2 {
                Text("Legacy classification: model weights remain in Media until a new scan.")
                    .font(.system(size: 11)).foregroundStyle(MapStyle.secondary).lineSpacing(2)
            }
        }
    }
}

private struct InspectorEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light)).foregroundStyle(MapStyle.secondary)
            Text(title).font(.system(size: 16, weight: .semibold)).padding(.top, 4)
            Text(message).font(.system(size: 12)).foregroundStyle(MapStyle.secondary).lineSpacing(3)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Neutral actions leave category color to the measurements.
struct InspectorButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        InspectorActionBody(configuration: configuration, compact: compact)
    }
    private struct InspectorActionBody: View {
        let configuration: ButtonStyle.Configuration
        let compact: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MapStyle.text.opacity(enabled ? 1 : 0.4))
                .padding(.horizontal, compact ? 0 : 12).padding(.vertical, compact ? 0 : 9)
                .background((configuration.isPressed ? MapStyle.line : hovering ? MapStyle.field : compact ? Color.clear : MapStyle.field.opacity(0.65)), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onHover { hovering = $0 }
        }
    }
}


/// Captures native list position, rather than interpreting row appearances as scroll state.
private struct ListPositionObserver: NSViewRepresentable {
    let entries: [StorageEntry]
    let position: String?
    let onPosition: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.entries = entries
        context.coordinator.position = position
        context.coordinator.onPosition = onPosition
        DispatchQueue.main.async { context.coordinator.connect(from: nsView) }
    }
    @MainActor final class Coordinator {
        var entries: [StorageEntry] = []
        var position: String?
        var onPosition: (String?) -> Void = { _ in }
        weak var table: NSTableView?
        private var observer: NSObjectProtocol?
        private var lastPosition: String?
        private var restoring = false
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

        func connect(from view: NSView) {
            if table == nil, let root = view.window?.contentView, let table = findTable(root), let clip = table.enclosingScrollView?.contentView {
                self.table = table
                clip.postsBoundsChangedNotifications = true
                observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.recordPosition() }
                }
            }
            guard let table, let position, position != lastPosition,
                  let row = entries.firstIndex(where: { $0.path == position }), row < table.numberOfRows,
                  let scroll = table.enclosingScrollView else { return }
            restoring = true
            let point = NSPoint(x: scroll.contentView.bounds.minX, y: table.rect(ofRow: row).minY)
            scroll.contentView.scroll(to: point)
            scroll.reflectScrolledClipView(scroll.contentView)
            lastPosition = position
            restoring = false
        }
        private func recordPosition() {
            guard !restoring, let table else { return }
            let row = table.rows(in: table.visibleRect).location
            guard row != NSNotFound, entries.indices.contains(row) else { return }
            let path = entries[row].path
            if path != lastPosition { lastPosition = path; onPosition(path) }
        }
        private func findTable(_ view: NSView) -> NSTableView? {
            if let table = view as? NSTableView, !(table is NSOutlineView) { return table }
            for subview in view.subviews { if let table = findTable(subview) { return table } }
            return nil
        }
    }
}
