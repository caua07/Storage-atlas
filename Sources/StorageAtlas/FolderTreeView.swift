import AppKit
import SwiftUI
import StorageCore

/// Native outline rows stay bounded by the pages loaded from the index.
struct FolderTreeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.currentFolder.map(shortPath) ?? model.scope)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(MapStyle.text)
                    .lineLimit(2).truncationMode(.middle)
                if model.summary?.isPartial == true {
                    Label("Partial coverage · some sizes may be unknown", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(MapStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            if model.summary != nil {
                FolderOutlineView(model: model)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "folder").font(.system(size: 24, weight: .light))
                    Text("No indexed folders yet").font(.system(size: 16, weight: .semibold)).foregroundStyle(MapStyle.text)
                    Text("Folders appear as storage is measured.").font(.system(size: 12))
                }.foregroundStyle(MapStyle.secondary).padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if !model.treeIssues.isEmpty {
                Rectangle().fill(MapStyle.line.opacity(0.6)).frame(height: 1)
                DisclosureGroup("Coverage notes · \(model.treeIssues.count)") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(model.treeIssues) { issue in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(shortPath(issue.path)).textSelection(.enabled)
                                    Text(issue.message).foregroundStyle(MapStyle.secondary)
                                }
                            }
                        }.font(.system(size: 11)).lineSpacing(2).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 120).padding(.top, 6)
                }.font(.system(size: 11)).tint(MapStyle.secondary).padding(16)
            }
            if let entry = model.selected {
                Rectangle().fill(MapStyle.line.opacity(0.6)).frame(height: 1)
                VStack(alignment: .leading, spacing: 10) {
                    Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 8) {
                        if entry.isDirectory {
                            Button("Open contents") { model.activateTreeEntry(entry) }
                        }
                        Button("Details") { model.inspectSelected() }
                        Spacer(minLength: 0)
                    }.buttonStyle(InspectorButtonStyle())
                }.padding(16)
            }
        }
        .task(id: model.summary?.id) {
            if let root = model.summary?.root { model.loadTreeChildren(path: root) }
        }
    }
}

private struct FolderOutlineView: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = FolderScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        scroll.contentView.postsBoundsChangedNotifications = true
        let outline = FolderOutline()
        outline.autoresizingMask = [.width]
        outline.headerView = nil
        outline.rowHeight = 48
        outline.intercellSpacing = NSSize(width: 0, height: 1)
        outline.indentationPerLevel = 10
        outline.selectionHighlightStyle = .regular
        outline.backgroundColor = .clear
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.usesAlternatingRowBackgroundColors = false
        outline.allowsEmptySelection = true
        outline.style = .plain
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("folder"))
        column.resizingMask = .autoresizingMask
        column.width = 356
        column.minWidth = 220
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.target = context.coordinator
        outline.doubleAction = #selector(Coordinator.activateRow)
        outline.onActivate = { context.coordinator.activateRow() }
        outline.onDismiss = { model.dismissTransient() }
        outline.menuBuilder = { point in context.coordinator.menu(at: point) }
        outline.setAccessibilityLabel("Folders. Expand with Right Arrow, collapse with Left Arrow, open with Return.")
        scroll.documentView = outline
        context.coordinator.outline = outline
        context.coordinator.observeScrolling(scroll.contentView)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.configure(model: model)
    }

    @MainActor final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        private var model: AppModel
        weak var outline: FolderOutline?
        private var nodes: [String: TreeItem] = [:]
        private var root: TreeItem?
        private var previousChildren: [String: [StorageEntry]] = [:]
        private var previousExpanded = Set<String>()
        private var previousLoading = Set<String>()
        private var previousMore = Set<String>()
        private var previousSnapshot: String?
        private var previousIssueIDs = Set<String>()
        private var requestedScrollPath: String?
        private var pendingScrollPath: String?
        private var scrollRestoreScheduled = false
        private var scrollRestoreRetries = 0
        private var previousClipSize: NSSize?
        private var observer: NSObjectProtocol?
        private var frameObserver: NSObjectProtocol?
        private var userScrollObserver: NSObjectProtocol?
        private var updating = false
        private var menuEntry: StorageEntry?

        init(model: AppModel) { self.model = model }
        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
            if let userScrollObserver { NotificationCenter.default.removeObserver(userScrollObserver) }
        }

        func observeScrolling(_ clip: NSClipView) {
            previousClipSize = clip.bounds.size
            clip.postsFrameChangedNotifications = true
            observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self, weak clip] _ in
                MainActor.assumeIsolated {
                    guard let self, let clip else { return }
                    self.recordGeometryChanges(clip)
                }
            }
            frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: clip, queue: .main) { [weak self, weak clip] _ in
                MainActor.assumeIsolated {
                    guard let self, let clip else { return }
                    self.recordGeometryChanges(clip)
                }
            }
            userScrollObserver = NotificationCenter.default.addObserver(forName: NSScrollView.didLiveScrollNotification, object: clip.enclosingScrollView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recordUserScroll() }
            }
        }

        private func recordGeometryChanges(_ clip: NSClipView) {
            if previousClipSize != clip.bounds.size {
                previousClipSize = clip.bounds.size
                // Scope notes and selection actions can change drawer height
                // after the first scroll. A resize is not a user scroll.
                requestedScrollPath = model.treeScrollPath
                pendingScrollPath = model.treeScrollPath
                scrollRestoreRetries = 0
                scheduleScrollRestoration()
            }
        }

        private func recordUserScroll() {
            guard !updating, let outline, outline.window != nil else { return }
            let rows = outline.rows(in: outline.visibleRect)
            guard rows.location != NSNotFound, rows.location < outline.numberOfRows,
                  let item = outline.item(atRow: rows.location) as? TreeItem else { return }
            pendingScrollPath = nil
            requestedScrollPath = item.path
            model.treeScrollPath = item.path
        }

        func configure(model: AppModel) {
            self.model = model
            guard let outline, let summary = model.summary else { return }
            let issueIDs = Set((model.issues + model.treeIssues).map(\.id))
            let changed = previousSnapshot != summary.id || previousChildren != model.treeChildren || previousExpanded != model.treeExpanded || previousLoading != model.treeLoading || previousMore != model.treeHasMore || previousIssueIDs != issueIDs
            updating = true
            defer { updating = false }
            if previousSnapshot != summary.id {
                requestedScrollPath = nil; pendingScrollPath = nil
            }
            if model.treeScrollPath != requestedScrollPath {
                requestedScrollPath = model.treeScrollPath
                pendingScrollPath = model.treeScrollPath
                scrollRestoreRetries = 0
            }
            if changed {
                if previousSnapshot != summary.id { nodes = [:] }
                let root = item(path: summary.root)
                root.isRoot = true
                root.entry = model.treeRoot
                self.root = root
                for entries in model.treeChildren.values {
                    for entry in entries { item(path: entry.path).entry = entry }
                }
                previousSnapshot = summary.id
                previousChildren = model.treeChildren
                previousExpanded = model.treeExpanded
                previousLoading = model.treeLoading
                previousMore = model.treeHasMore
                previousIssueIDs = issueIDs
                outline.reloadData()
                applyExpansion(root)
            }
            let selected = model.treeSelectedPath ?? model.selected?.path ?? model.currentFolder
            if let selected, let item = nodes[selected] {
                let row = outline.row(forItem: item)
                if row >= 0 && outline.selectedRow != row {
                    outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
            }
            scheduleScrollRestoration()
        }

        private func scheduleScrollRestoration() {
            guard pendingScrollPath != nil, !scrollRestoreScheduled else { return }
            scrollRestoreScheduled = true
            // Expansion and reload update the outline's document geometry after
            // this SwiftUI update. Retain the request until its row is available.
            DispatchQueue.main.async { [weak self] in self?.restorePendingScroll() }
        }

        private func restorePendingScroll() {
            scrollRestoreScheduled = false
            guard let path = pendingScrollPath, let outline, let item = nodes[path] else { return }
            let row = outline.row(forItem: item)
            guard row >= 0, let scroll = outline.enclosingScrollView else { return }
            updating = true
            defer { updating = false }
            scroll.layoutSubtreeIfNeeded()
            outline.layoutSubtreeIfNeeded()
            let point = NSPoint(x: scroll.contentView.bounds.minX, y: outline.rect(ofRow: row).minY)
            scroll.contentView.scroll(to: point)
            outline.scrollRowToVisible(row)
            scroll.reflectScrolledClipView(scroll.contentView)
            let rowRect = outline.rect(ofRow: row), visible = outline.visibleRect
            guard rowRect.minY >= visible.minY - 0.5, rowRect.maxY <= visible.maxY + 0.5 else {
                if scrollRestoreRetries == 0 {
                    scrollRestoreRetries += 1
                    scrollRestoreScheduled = true
                    DispatchQueue.main.async { [weak self] in self?.restorePendingScroll() }
                }
                return
            }
            pendingScrollPath = nil
        }

        private func item(path: String) -> TreeItem {
            if let item = nodes[path] { return item }
            let item = TreeItem(path: path)
            nodes[path] = item
            return item
        }

        private func children(_ parent: TreeItem) -> [TreeItem] {
            guard parent.isRoot || parent.entry?.isDirectory == true else { return [] }
            let entries = model.treeChildren[parent.path]
            var rows = (entries ?? []).map { item(path: $0.path) }
            if model.treeLoading.contains(parent.path) || entries == nil {
                let loading = item(path: parent.path + "\u{0}loading")
                loading.placeholderParent = parent.path; loading.isLoading = true
                rows.append(loading)
            } else if model.treeHasMore.contains(parent.path) {
                let more = item(path: parent.path + "\u{0}more")
                more.placeholderParent = parent.path; more.isMore = true
                rows.append(more)
            }
            return rows
        }

        private func applyExpansion(_ item: TreeItem) {
            guard let outline else { return }
            if model.treeExpanded.contains(item.path) {
                outline.expandItem(item)
                for child in children(item) where !child.isMore && !child.isLoading { applyExpansion(child) }
            } else { outline.collapseItem(item) }
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let item = item as? TreeItem else { return root == nil ? 0 : 1 }
            return children(item).count
        }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let item = item as? TreeItem else { return root! }
            return children(item)[index]
        }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let item = item as? TreeItem else { return false }
            guard item.isRoot || item.entry?.isDirectory == true else { return false }
            return model.treeChildren[item.path] == nil || !(model.treeChildren[item.path]?.isEmpty ?? true) || model.treeLoading.contains(item.path) || model.treeHasMore.contains(item.path)
        }
        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            FolderRowView()
        }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? TreeItem else { return nil }
            if item.isMore || item.isLoading {
                let cell = NSTableCellView()
                let text = NSTextField(labelWithString: item.isMore ? "Load more…" : "Reading index…")
                text.font = .systemFont(ofSize: 11)
                text.textColor = NSColor(MapStyle.secondary)
                cell.addSubview(text)
                text.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor), text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4)])
                cell.setAccessibilityLabel(item.isMore ? "Load more children. Press Return." : "Loading children")
                return cell
            }
            let entry = item.entry
            let bytes = item.isRoot ? model.summary?.allocatedBytes ?? 0 : entry?.allocatedBytes ?? 0
            let parentBytes: Int64? = entry.flatMap { e in
                if e.parent == model.summary?.root { return model.summary?.allocatedBytes }
                return nodes[e.parent]?.entry?.allocatedBytes
            }
            let retainedIssues = model.issues + model.treeIssues
            let directGap = retainedIssues.contains(where: { $0.path == item.path })
            let descendantGap = retainedIssues.contains(where: { $0.path != item.path && StorageNavigation.contains($0.path, in: item.path) })
            let share = directGap ? nil : parentBytes.flatMap { StorageNavigation.share(bytes: bytes, parentBytes: $0) }
            let shareText = share.map { $0.formatted(.percent.precision(.fractionLength(1))) + " of parent" } ?? ""
            let baseKind = item.isRoot || entry?.isDirectory == true ? "Folder" : entry?.isSymbolicLink == true ? "Symbolic link" : "File"
            let kind = baseKind + (directGap && bytes == 0 ? " · no access" : directGap || descendantGap ? " · partial" : "")
            let sizeText = directGap && bytes == 0 ? "Unknown size" : directGap ? byteString(bytes) + " measured" : byteString(bytes)
            let name = item.isRoot ? (model.summary?.scopeKind == .global ? "Mac" : URL(fileURLWithPath: item.path).lastPathComponent) : entry?.name ?? item.path
            let cell = FolderCell()
            cell.name.stringValue = name
            cell.detail.stringValue = kind + (model.currentFolder == item.path ? " · current" : "")
            cell.size.stringValue = sizeText
            cell.share.stringValue = shareText
            cell.icon.image = NSImage(systemSymbolName: item.isRoot || entry?.isDirectory == true ? "folder" : entry?.isSymbolicLink == true ? "link" : entry?.category.symbol ?? "doc", accessibilityDescription: nil)
            cell.icon.contentTintColor = entry?.isDirectory == true || item.isRoot ? NSColor(MapStyle.secondary) : MapStyle.nativeColor(entry?.category ?? .other)
            cell.toolTip = item.path
            cell.setAccessibilityLabel("\(name), \(kind), \(sizeText)\(directGap && bytes == 0 ? "" : " on disk")\(shareText.isEmpty ? "" : ", " + shareText), \(item.path)")
            return cell
        }
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let outline, let item = outline.item(atRow: outline.selectedRow) as? TreeItem, let entry = item.entry else { return }
            model.selectTreeEntry(entry)
            recordUserScroll()
        }
        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !updating, let item = notification.userInfo?["NSObject"] as? TreeItem else { return }
            if !model.treeExpanded.contains(item.path) { model.toggleTreeExpansion(path: item.path) }
        }
        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !updating, let item = notification.userInfo?["NSObject"] as? TreeItem else { return }
            if model.treeExpanded.contains(item.path) { model.toggleTreeExpansion(path: item.path) }
        }
        @objc func activateRow() {
            guard let outline, let item = outline.item(atRow: outline.selectedRow) as? TreeItem else { return }
            if item.isMore, let parent = item.placeholderParent { model.loadMoreTree(path: parent) }
            else if item.isRoot { model.goGlobal() }
            else if let entry = item.entry { model.activateTreeEntry(entry) }
        }
        func menu(at point: NSPoint) -> NSMenu? {
            guard let outline, let item = outline.item(atRow: outline.row(at: point)) as? TreeItem, let entry = item.entry else { return nil }
            menuEntry = entry
            let menu = NSMenu()
            let actions: [(String, Selector, String)] = [
                (entry.isDirectory ? "Open contents" : "Open containing folder", #selector(openFromMenu), "folder"),
                ("Details", #selector(detailsFromMenu), "info.circle"),
                ("Reveal in Finder", #selector(revealFromMenu), "arrow.up.forward.app"),
                ("Copy path", #selector(copyFromMenu), "doc.on.doc")
            ]
            for (index, action) in actions.enumerated() {
                if index == 2 { menu.addItem(.separator()) }
                let item = NSMenuItem(title: action.0, action: action.1, keyEquivalent: "")
                item.image = NSImage(systemSymbolName: action.2, accessibilityDescription: nil)
                item.target = self
                menu.addItem(item)
            }
            return menu
        }
        @objc private func openFromMenu() { if let entry = menuEntry { if entry.isDirectory { model.activateTreeEntry(entry) } else { model.openContainingFolder(entry) } } }
        @objc private func detailsFromMenu() { if let entry = menuEntry { model.inspect(entry) } }
        @objc private func revealFromMenu() { if let entry = menuEntry { model.reveal(entry) } }
        @objc private func copyFromMenu() { if let entry = menuEntry { model.copyPath(entry) } }
    }
}

private final class TreeItem: NSObject {
    let path: String
    var entry: StorageEntry?
    var isRoot = false
    var isMore = false
    var isLoading = false
    var placeholderParent: String?
    init(path: String) { self.path = path }
}

/// Keep native row cells inside the visible drawer when the window/scrollbar changes size.
private final class FolderScrollView: NSScrollView {
    override func tile() {
        super.tile()
        guard let outline = documentView as? NSOutlineView, contentSize.width > 0 else { return }
        let width = contentSize.width
        if abs(outline.frame.width - width) > 0.5 {
            outline.setFrameSize(NSSize(width: width, height: outline.frame.height))
        }
        if let column = outline.tableColumns.first, abs(column.width - width) > 0.5 {
            column.width = width
        }
    }
}

private final class FolderOutline: NSOutlineView {
    var onActivate: () -> Void = {}
    var onDismiss: () -> Void = {}
    var menuBuilder: (NSPoint) -> NSMenu? = { _ in nil }
    private var stableViewportWidth: CGFloat? {
        if let width = enclosingScrollView?.contentSize.width, width > 0 { return width }
        if let width = tableColumns.first?.width, width > 0 { return width }
        return bounds.width > 0 ? bounds.width : nil
    }
    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var rect = super.frameOfCell(atColumn: column, row: row)
        // visibleRect is empty before a freshly reopened outline is attached.
        // Never cache zero-width cells from that transient layout state.
        if let width = stableViewportWidth {
            let originX = enclosingScrollView?.contentView.bounds.minX ?? bounds.minX
            rect.size.width = max(0, originX + width - rect.minX)
        }
        return rect
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onActivate()
        case 53: onDismiss()
        default: super.keyDown(with: event)
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? { menuBuilder(convert(event.locationInWindow, from: nil)) }
}

private final class FolderCell: NSTableCellView {
    let icon = NSImageView()
    let name = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    let size = NSTextField(labelWithString: "")
    let share = NSTextField(labelWithString: "")
    private var valuesTrailingConstraint: NSLayoutConstraint?

    override func layout() {
        // A reopened view may be laid out before it has a viewport. Clear any
        // previous correction until both views are attached and sizes are valid.
        var ancestor = superview
        while let view = ancestor, !(view is NSOutlineView) { ancestor = view.superview }
        var inset: CGFloat = -10
        if let outline = ancestor as? NSOutlineView, let scroll = outline.enclosingScrollView,
           window != nil, outline.window === window, scroll.contentSize.width > 0,
           outline.bounds.width > 0, bounds.width > 0 {
            let viewport = NSRect(x: scroll.contentView.bounds.minX, y: outline.bounds.minY,
                                  width: scroll.contentSize.width, height: 1)
            let visibleRight = convert(viewport, from: outline).maxX
            if visibleRight.isFinite && visibleRight > 0 {
                inset -= max(0, bounds.maxX - visibleRight)
            }
        }
        if let valuesTrailingConstraint, abs(valuesTrailingConstraint.constant - inset) > 0.5 {
            valuesTrailingConstraint.constant = inset
        }
        super.layout()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.textColor = NSColor(MapStyle.text)
        detail.font = .systemFont(ofSize: 11); detail.textColor = NSColor(MapStyle.secondary)
        size.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        size.textColor = NSColor(MapStyle.text)
        share.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        share.textColor = NSColor(MapStyle.secondary)
        name.lineBreakMode = .byTruncatingMiddle; detail.lineBreakMode = .byTruncatingTail
        size.alignment = .right; share.alignment = .right
        let titles = NSStackView(views: [name, detail]); titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 3
        let values = NSStackView(views: [size, share]); values.orientation = .vertical; values.alignment = .trailing; values.spacing = 3
        addSubview(icon); addSubview(titles); addSubview(values)
        let cellViews: [NSView] = [icon, titles, values]
        for view in cellViews { view.translatesAutoresizingMaskIntoConstraints = false }
        let valueTrailing = values.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        valuesTrailingConstraint = valueTrailing
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            valueTrailing,
            values.centerYAnchor.constraint(equalTo: centerYAnchor),
            values.widthAnchor.constraint(equalToConstant: 112),
            titles.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            titles.trailingAnchor.constraint(equalTo: values.leadingAnchor, constant: -8),
            titles.centerYAnchor.constraint(equalTo: centerYAnchor),
            name.widthAnchor.constraint(lessThanOrEqualTo: titles.widthAnchor),
            detail.widthAnchor.constraint(lessThanOrEqualTo: titles.widthAnchor),
            size.widthAnchor.constraint(lessThanOrEqualTo: values.widthAnchor),
            share.widthAnchor.constraint(lessThanOrEqualTo: values.widthAnchor)
        ])
        titles.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titles.setContentHuggingPriority(.defaultLow, for: .horizontal)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        values.setContentCompressionResistancePriority(.required, for: .horizontal)
        size.lineBreakMode = .byTruncatingTail
        share.lineBreakMode = .byTruncatingTail
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Draw neutral native row feedback without changing outline selection or keyboard behavior.
private final class FolderRowView: NSTableRowView {
    private var hoverArea: NSTrackingArea?
    private var hovering = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func drawBackground(in dirtyRect: NSRect) {
        if hovering && !isSelected {
            NSColor(MapStyle.field).withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 2), xRadius: 8, yRadius: 8).fill()
        }
    }
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        NSColor(MapStyle.field).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 2), xRadius: 8, yRadius: 8).fill()
    }
}
