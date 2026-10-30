import AppKit
import QuartzCore
import SwiftUI
import StorageCore

struct TreemapCanvasView: NSViewRepresentable {
    let nodes: [TreemapNode]
    let selectedPath: String?
    let matchingPaths: Set<String>
    let search: String
    let category: StorageCategory?
    let onHover: (TreemapNode?) -> Void
    let onSelect: (TreemapNode) -> Void
    let onZoom: (TreemapNode) -> Void
    let onReveal: (TreemapNode) -> Void
    let onCopy: (TreemapNode) -> Void
    let onUp: () -> Void
    let onGlobal: () -> Void
    let onDismiss: () -> Void

    func makeNSView(context: Context) -> StorageMapSurface { StorageMapSurface() }
    func updateNSView(_ view: StorageMapSurface, context: Context) {
        view.onHover = onHover; view.onSelect = onSelect; view.onZoom = onZoom
        view.onReveal = onReveal; view.onCopy = onCopy
        view.onUp = onUp; view.onGlobal = onGlobal
        view.onDismiss = onDismiss
        view.configure(nodes: nodes, selectedPath: selectedPath, matchingPaths: matchingPaths,
                       hasSearch: !search.isEmpty, category: category)
    }
}

/// A single native surface draws the entire frontier. No file owns a SwiftUI view.
final class StorageMapSurface: NSView {
    private var nodes: [TreemapNode] = []
    private var tiles: [TreemapTile] = []
    private var groups: [TreemapGroup] = []
    private struct GroupHeader { let node: TreemapNode; let rect: CGRect }
    private var headers: [GroupHeader] = []
    private var selectedPath: String?
    private var matchingPaths: Set<String> = []
    private var matchingAncestors: Set<String> = []
    private var matchingRollups: Set<String> = []
    private var matchGeneration = 0
    private var matchingWorker: Task<(Set<String>, Set<String>), Never>?
    var isResolvingMatches: Bool { matchingWorker != nil }
    private var hasSearch = false
    private var category: StorageCategory?
    private var hoveredID: String?
    private var tracking: NSTrackingArea?
    private var layoutGeneration = 0
    private var lastLayoutSize = CGSize.zero
    private var menuNode: TreemapNode?
    private var displayedScope: String?
    var onHover: (TreemapNode?) -> Void = { _ in }
    var onSelect: (TreemapNode) -> Void = { _ in }
    var onZoom: (TreemapNode) -> Void = { _ in }
    var onReveal: (TreemapNode) -> Void = { _ in }
    var onCopy: (TreemapNode) -> Void = { _ in }
    var onUp: () -> Void = {}
    var onGlobal: () -> Void = {}
    var onDismiss: () -> Void = {}

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Storage treemap. Open the items list to inspect files with the keyboard.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(nodes newNodes: [TreemapNode], selectedPath: String?, matchingPaths: Set<String>, hasSearch: Bool, category: StorageCategory?) {
        let needsLayout = nodes != newNodes
        nodes = newNodes
        self.selectedPath = selectedPath
        if self.matchingPaths != matchingPaths {
            self.matchingPaths = matchingPaths
            matchingAncestors = []; matchingRollups = []
            scheduleMatches()
        }
        self.hasSearch = hasSearch; self.category = category
        if needsLayout { scheduleLayout() }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if lastLayoutSize != bounds.size { scheduleLayout() }
    }

    private func scheduleLayout() {
        let size = bounds.size
        guard size.width > 0 && size.height > 0 else { return }
        lastLayoutSize = size; layoutGeneration += 1
        let generation = layoutGeneration, source = nodes
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                TreemapLayout.layout(nodes: source, in: CGRect(origin: .zero, size: size), minimumTileArea: 20)
            }.value
            guard let self, self.layoutGeneration == generation else { return }
            let scope = self.focusPath(source)
            let changesScope = !self.tiles.isEmpty && self.displayedScope != scope
            self.tiles = result.tiles; self.groups = result.groups
            self.headers = self.groupHeaders(result.groups)
            self.displayedScope = scope
            self.scheduleMatches()
            // Fade the backing contents once on navigation. The measured rectangles
            // land immediately; neither layout nor pointer targets interpolate.
            if changesScope && !MapStyle.reduceMotion {
                let fade = CATransition()
                fade.type = .fade; fade.duration = 0.18
                fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.layer?.add(fade, forKey: "scopeContents")
            } else {
                self.layer?.removeAnimation(forKey: "scopeContents")
            }
            self.needsDisplay = true
        }
    }

    private func scheduleMatches() {
        matchGeneration += 1
        matchingWorker?.cancel()
        matchingWorker = nil
        let generation = matchGeneration, paths = matchingPaths
        let leafPaths = Set(tiles.filter { !$0.node.isRollup }.map { $0.node.path })
        let groupPaths = Set(groups.map { $0.node.path })
        let rollups = tiles.filter { $0.node.isRollup }.map { $0.node }
        let rollupIDs = Dictionary(grouping: rollups, by: \.path).mapValues { Set($0.map(\.id)) }
        guard !paths.isEmpty else { matchingAncestors = []; matchingRollups = []; return }
        let worker = Task.detached(priority: .userInitiated) {
            do {
                let result = try TreemapHighlightProjection.resolve(matchingPaths: paths, leafPaths: leafPaths,
                    groupPaths: groupPaths, rollupIDsByParent: rollupIDs)
                return (result.leafPaths, result.rollupIDs)
            } catch { return (Set<String>(), Set<String>()) }
        }
        matchingWorker = worker
        Task { [weak self] in
            let result = await worker.value
            guard let self, self.matchGeneration == generation else { return }
            self.matchingWorker = nil
            self.matchingAncestors = result.0; self.matchingRollups = result.1
            self.needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
        super.updateTrackingAreas()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(MapStyle.canvas).setFill()
        bounds.fill()
        for group in groups where group.rect.intersects(dirtyRect) {
            NSColor(MapStyle.chrome).setFill()
            groupShape(group.rect).fill()
        }
        for tile in tiles where tile.rect.intersects(dirtyRect) {
            drawTile(tile)
        }
        // Group annotations add no bytes, and reserve no proportional area.
        for group in groups where group.rect.intersects(dirtyRect) {
            let active = hoveredID == group.node.id || selectedPath == group.node.path
            NSColor(MapStyle.text).withAlphaComponent(active ? 0.48 : 0.12).setStroke()
            let border = groupShape(group.rect); border.lineWidth = active ? 1.5 : 1; border.stroke()
        }
        for header in headers where header.rect.intersects(dirtyRect) {
            drawHeader(header)
        }
        // A contained file is not an exact selection of its aggregate. A dashed
        // outline marks the nearest real container while details name that path.
        let focus = focusPath(nodes)
        if let path = selectedPath, let focus, StorageNavigation.contains(path, in: focus),
           !tiles.contains(where: { !$0.node.isRollup && $0.node.path == path }) {
            let containers = tiles.filter { !$0.node.isRollup && $0.node.isDirectory && path.hasPrefix($0.node.path + "/") }.map { ($0.node.path, $0.rect) }
                + groups.filter { path.hasPrefix($0.node.path == "/" ? "/" : $0.node.path + "/") }.map { ($0.node.path, $0.rect) }
            let rect = containers.max(by: { $0.0.count < $1.0.count })?.1 ?? bounds
            NSColor(MapStyle.accent).withAlphaComponent(0.85).setStroke()
            let outline = roundedShape(rect.insetBy(dx: 4, dy: 4), radius: 8)
            outline.lineWidth = 1; outline.setLineDash([4, 3], count: 2, phase: 0); outline.stroke()
        }
    }

    private func groupHeaders(_ groups: [TreemapGroup]) -> [GroupHeader] {
        var result: [GroupHeader] = []
        for group in groups.sorted(by: { $0.depth > $1.depth }) {
            guard group.rect.width > 190, group.rect.height > 90, group.rect.width * group.rect.height > 28000 else { continue }
            let titleWidth = (group.node.name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width
            let sizeWidth = (byteString(group.node.bytes) as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)]).width
            let rect = CGRect(x: group.rect.minX + 8, y: group.rect.minY + 8,
                              width: min(group.rect.width - 16, min(360, titleWidth + sizeWidth + 36)), height: 28)
            guard !result.contains(where: { $0.rect.insetBy(dx: -5, dy: -5).intersects(rect) }) else { continue }
            result.append(GroupHeader(node: group.node, rect: rect))
        }
        return result
    }

    private func drawTile(_ tile: TreemapTile) {
        let rect = paintedRect(tile.rect)
        guard rect.width > 0 && rect.height > 0 else { return }
        let node = tile.node, match = isMatch(node)
        // Ordinary folders and exact rollups contain mixed measured content.
        // A category fill is reserved for files or a rule-backed artifact.
        let mixed = node.isRollup || (node.isDirectory && node.entry?.rule == nil)
        let base = mixed ? NSColor(srgbRed: 0.19, green: 0.20, blue: 0.21, alpha: 1) : MapStyle.nativeColor(node.category)
        var color = match ? base : base.blended(withFraction: 0.72, of: NSColor(MapStyle.canvas)) ?? base
        if hoveredID == node.id { color = color.blended(withFraction: 0.10, of: NSColor(MapStyle.text)) ?? color }
        let shape = tileShape(tile.rect)
        color.setFill(); shape.fill()
        let selected = selectedPath == node.path && !node.isRollup
        if selected || hoveredID == node.id {
            let focused = window?.firstResponder === self
            let outlineColor = selected && focused ? NSColor(MapStyle.accent) : NSColor(MapStyle.text)
            outlineColor.withAlphaComponent(selected ? 0.95 : 0.65).setStroke()
            let outline = roundedShape(rect.insetBy(dx: 1, dy: 1), radius: tileRadius(rect) - 1)
            outline.lineWidth = selected ? 2 : 1; outline.stroke()
        } else if (hasSearch || category != nil) && match {
            NSColor(MapStyle.text).withAlphaComponent(0.38).setStroke()
            let outline = roundedShape(rect.insetBy(dx: 0.5, dy: 0.5), radius: tileRadius(rect) - 0.5)
            outline.lineWidth = 1; outline.stroke()
        }
        guard rect.width >= 50 && rect.height >= 22 else { return }
        let inset: CGFloat = rect.width >= 180 && rect.height >= 100 ? 16 : rect.width >= 100 ? 10 : 5
        let textColor = NSColor(MapStyle.text).withAlphaComponent(match ? 1 : 0.60)
        let width = rect.width - inset * 2
        let large = rect.width > 300 && rect.height > 180
        let medium = rect.width > 170 && rect.height > 95
        let fontSize: CGFloat = large ? 18 : medium ? 13 : 11
        var labelY = rect.minY + inset
        for header in headers where header.rect.intersects(CGRect(x: rect.minX, y: labelY, width: rect.width, height: fontSize + 4)) {
            labelY = max(labelY, header.rect.maxY + 10)
        }
        guard labelY + fontSize + 4 < rect.maxY else { return }
        drawLine(node.name, in: CGRect(x: rect.minX + inset, y: labelY, width: width, height: fontSize + 4),
                 font: .systemFont(ofSize: fontSize, weight: .semibold), color: textColor)
        let sizeFont: CGFloat = large ? 26 : medium ? 18 : 11
        let sizeY = labelY + fontSize + (medium ? 10 : 5)
        if sizeY + sizeFont + 4 < rect.maxY - inset && width >= 62 {
            drawLine(byteString(node.bytes), in: CGRect(x: rect.minX + inset, y: sizeY, width: width, height: sizeFont + 5),
                     font: .monospacedDigitSystemFont(ofSize: sizeFont, weight: medium ? .medium : .regular), color: textColor)
        }
        if rect.height > 100 && width > 115 && sizeY + sizeFont + 16 < rect.maxY - inset - 16 {
            let kind = node.isRollup ? "\(node.fileCount.formatted()) files · combined" : node.isDirectory ? "Folder · \(node.fileCount.formatted()) files" : node.entry?.isSymbolicLink == true ? "Symbolic link" : node.category.title
            drawLine(kind, in: CGRect(x: rect.minX + inset, y: rect.maxY - inset - 16, width: width, height: 16),
                     font: .systemFont(ofSize: 11), color: textColor.withAlphaComponent(match ? 0.86 : 0.60))
        }
    }

    private func drawHeader(_ header: GroupHeader) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        shadow.shadowOffset = NSSize(width: 0, height: 2)
        shadow.shadowBlurRadius = 7
        shadow.set()
        NSColor(MapStyle.panel).setFill()
        roundedShape(header.rect, radius: 8).fill()
        NSGraphicsContext.restoreGraphicsState()
        let size = byteString(header.node.bytes)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let sizeWidth = ceil((size as NSString).size(withAttributes: [.font: font]).width)
        let textRect = header.rect.insetBy(dx: 10, dy: 6)
        drawLine(header.node.name, in: CGRect(x: textRect.minX, y: textRect.minY, width: max(0, textRect.width - sizeWidth - 14), height: 17),
                 font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor(MapStyle.text))
        drawLine(size, in: CGRect(x: textRect.maxX - sizeWidth, y: textRect.minY + 1, width: sizeWidth, height: 16),
                 font: font, color: NSColor(MapStyle.secondary))
    }

    private func focusPath(_ source: [TreemapNode]) -> String? {
        source.first.map { node in node.entry.map { $0.parent.isEmpty ? $0.path : $0.parent } ?? node.path }
    }

    private func paintedRect(_ rect: CGRect) -> CGRect {
        let side = min(rect.width, rect.height)
        let inset: CGFloat = side >= 24 ? 2.5 : side >= 10 ? 1.5 : min(0.5, side * 0.2)
        return rect.insetBy(dx: inset, dy: inset)
    }

    private func tileRadius(_ rect: CGRect) -> CGFloat {
        min(rect.width, rect.height) >= 60 ? 10 : min(5, min(rect.width, rect.height) * 0.18)
    }

    private func roundedShape(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: max(0, radius), yRadius: max(0, radius))
    }

    private func tileShape(_ rect: CGRect) -> NSBezierPath {
        let painted = paintedRect(rect)
        return roundedShape(painted, radius: tileRadius(painted))
    }

    private func groupShape(_ rect: CGRect) -> NSBezierPath {
        roundedShape(rect.insetBy(dx: 1.5, dy: 1.5), radius: 12)
    }

    private func drawLine(_ text: String, in rect: CGRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func isMatch(_ node: TreemapNode) -> Bool {
        guard hasSearch || category != nil else { return true }
        if node.isRollup { return matchingRollups.contains(node.id) }
        if matchingAncestors.contains(node.path) { return true }
        if hasSearch { return false }
        return !node.isDirectory && category == node.category
    }

    private func hit(_ point: NSPoint) -> TreemapNode? {
        if let header = headers.first(where: { roundedShape($0.rect, radius: 8).contains(point) }) { return header.node }
        if let tile = tiles.first(where: { tileShape($0.rect).contains(point) }) { return tile.node }
        return groups.reversed().first(where: { groupShape($0.rect).contains(point) })?.node
    }

    override func becomeFirstResponder() -> Bool { needsDisplay = true; return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }

    override func mouseMoved(with event: NSEvent) {
        let node = hit(convert(event.locationInWindow, from: nil))
        if hoveredID != node?.id {
            hoveredID = node?.id; onHover(node); needsDisplay = true
        }
    }
    override func mouseExited(with event: NSEvent) {
        hoveredID = nil; onHover(nil); needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let node = hit(convert(event.locationInWindow, from: nil)) else { return }
        if event.clickCount > 1 { onZoom(node) } else { onSelect(node) }
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onDismiss()
        case 51, 117: onUp()
        case 115: onGlobal()
        default: super.keyDown(with: event)
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let node = hit(convert(event.locationInWindow, from: nil)) else { return nil }
        menuNode = node
        let menu = NSMenu()
        if node.isDirectory || node.isRollup {
            let zoom = NSMenuItem(title: "Open in map", action: #selector(zoomFromMenu), keyEquivalent: "")
            zoom.target = self; menu.addItem(zoom)
        }
        if node.entry != nil {
            let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(revealFromMenu), keyEquivalent: "")
            reveal.target = self; menu.addItem(reveal)
            let copy = NSMenuItem(title: "Copy path", action: #selector(copyFromMenu), keyEquivalent: "")
            copy.target = self; menu.addItem(copy)
        }
        return menu
    }
    @objc private func zoomFromMenu() { if let node = menuNode { onZoom(node) } }
    @objc private func revealFromMenu() { if let node = menuNode { onReveal(node) } }
    @objc private func copyFromMenu() { if let node = menuNode { onCopy(node) } }
}

