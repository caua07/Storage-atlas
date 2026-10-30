import Foundation
import CoreGraphics

/// A measured partition of its parent's allocation. Children replace this node's area;
/// the parent itself is only an outline when expanded.
public struct TreemapNode: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    /// Rollups point at their real parent, so zooming can inspect the omitted entries.
    public let path: String
    public let bytes: Int64
    public let category: StorageCategory
    public let isDirectory: Bool
    public let fileCount: Int64
    public let entry: StorageEntry?
    public let children: [TreemapNode]
    public let isRollup: Bool

    public init(id: String, name: String, path: String, bytes: Int64, category: StorageCategory = .other,
                isDirectory: Bool = false, fileCount: Int64 = 1, entry: StorageEntry? = nil,
                children: [TreemapNode] = [], isRollup: Bool = false) {
        self.id = id; self.name = name; self.path = path; self.bytes = max(0, bytes)
        self.category = category; self.isDirectory = isDirectory; self.fileCount = max(0, fileCount)
        self.entry = entry; self.children = children; self.isRollup = isRollup
    }

    public init(entry: StorageEntry, children: [TreemapNode] = []) {
        self.init(id: entry.path, name: entry.name, path: entry.path, bytes: entry.allocatedBytes,
                  category: entry.category, isDirectory: entry.isDirectory, fileCount: entry.fileCount,
                  entry: entry, children: children)
    }

    fileprivate static func rollup(parent: String, bytes: Int64, count: Int64, suffix: String,
                                   category: StorageCategory = .other) -> TreemapNode {
        TreemapNode(id: parent + "\u{0}rollup:" + suffix, name: "Other entries", path: parent,
                    bytes: bytes, category: category, isDirectory: true, fileCount: count, isRollup: true)
    }
}

public struct TreemapTile: Identifiable, Sendable, Equatable {
    public let node: TreemapNode
    public let rect: CGRect
    public let depth: Int
    public var id: String { node.id }
    public var isRollup: Bool { node.isRollup }
}

/// Non-additive folder annotation: its rectangle is already occupied by descendant tiles.
public struct TreemapGroup: Identifiable, Sendable, Equatable {
    public let node: TreemapNode
    public let rect: CGRect
    public let depth: Int
    public var id: String { node.id }
}

public struct TreemapResult: Sendable, Equatable {
    public let tiles: [TreemapTile]
    public let groups: [TreemapGroup]
    public init(tiles: [TreemapTile], groups: [TreemapGroup]) { self.tiles = tiles; self.groups = groups }

    public func tile(at point: CGPoint) -> TreemapTile? {
        tiles.first { $0.rect.contains(point) }
    }
}

/// Bounded index projection. Call on a worker queue; no filesystem traversal or file views
/// are created here. Search is intentionally separate from this unchanged denominator.
public enum TreemapProjection {
    public static func load(index: StorageIndex, scanID: String, rootPath: String,
                            maxDepth: Int = 4, maxNodes: Int = 1800,
                            childrenLimit: Int = 128) throws -> [TreemapNode] {
        var budget = max(2, maxNodes)
        let rootEntry = try index.entry(scanID: scanID, path: rootPath)
        let rootBytes = rootEntry?.allocatedBytes
        let limit = max(1, min(1000, childrenLimit))

        func level(parent: String, expected: StorageEntry?, depth: Int, hops: Int) throws -> [TreemapNode]? {
            try Task.checkCancellation()
            guard budget >= 2 else { return nil }
            let batch = try index.mapChildren(scanID: scanID, parent: parent, limit: min(limit, budget - 1))
            var nodes = batch.entries.filter { $0.allocatedBytes > 0 }.map { TreemapNode(entry: $0) }
            if batch.remainderBytes > 0 {
                nodes.append(.rollup(parent: parent, bytes: batch.remainderBytes,
                                     count: batch.remainderCount, suffix: "index"))
            }
            let represented = nodes.reduce(Int64(0)) { $0 + $1.bytes }
            if let expected {
                // A concurrent refresh can advance descendants between queries. Never scale
                // overfull children to an older parent total; retain that parent's exact tile.
                guard represented <= expected.allocatedBytes else { return nil }
                if represented < expected.allocatedBytes {
                    let count = max(0, expected.fileCount - nodes.reduce(Int64(0)) { $0 + $1.fileCount })
                    nodes.append(.rollup(parent: parent, bytes: expected.allocatedBytes - represented,
                                         count: count, suffix: "unexpanded"))
                }
            }
            guard !nodes.isEmpty, nodes.count <= budget else { return nil }
            budget -= nodes.count
            // Single-child chains do not spend the detail-depth allowance. This brings
            // Users/name and similarly deep ordinary paths into view without unbounded work.
            let nextDepth = depth + (nodes.count > 1 ? 1 : 0)
            if nextDepth < max(1, maxDepth), hops < 32 {
                for i in nodes.indices {
                    let node = nodes[i]
                    guard budget >= 2, let entry = node.entry, entry.isDirectory,
                          !entry.isRuleRoot, !entry.name.lowercased().hasSuffix(".app"),
                          rootBytes == nil || Double(node.bytes) >= Double(rootBytes!) / Double(max(2, maxNodes))
                    else { continue }
                    if let children = try level(parent: entry.path, expected: entry, depth: nextDepth, hops: hops + 1) {
                        nodes[i] = TreemapNode(entry: entry, children: children)
                    }
                }
            }
            return nodes
        }

        if let nodes = try level(parent: rootPath, expected: rootEntry, depth: 0, hops: 0) { return nodes }
        if let rootEntry, rootEntry.allocatedBytes > 0 { return [TreemapNode(entry: rootEntry)] }
        return []
    }
}

/// Deterministic squarified rectangles with no padding removed from measured area.
/// Render borders/labels inside the returned rectangles. Pixel-small siblings combine
/// into a measured rollup; zooming their real parent queries finer detail from the index.
public enum TreemapLayout {
    public static func layout(nodes: [TreemapNode], in bounds: CGRect,
                              minimumTileArea: Double = 20) -> TreemapResult {
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.minX.isFinite, bounds.minY.isFinite,
              bounds.width > 0, bounds.height > 0, (bounds.width * bounds.height).isFinite
        else { return TreemapResult(tiles: [], groups: []) }
        var tiles: [TreemapTile] = []
        var groups: [TreemapGroup] = []
        let minimum = minimumTileArea.isFinite ? max(0, minimumTileArea) : 0

        func visit(_ input: [TreemapNode], rect: CGRect, depth: Int) {
            var siblings = input.filter { $0.bytes > 0 }.sorted(by: ordered)
            guard !siblings.isEmpty else { return }
            let total = siblings.reduce(0.0) { $0 + Double($1.bytes) }
            let area = Double(rect.width * rect.height)
            let small = siblings.filter { Double($0.bytes) / total * area < minimum }
            if small.count > 1 {
                let tinyIDs = Set(small.map(\.id))
                siblings.removeAll { tinyIDs.contains($0.id) }
                let parent = small.first?.entry?.parent ?? commonParent(small.map(\.path))
                let category = small.allSatisfy { $0.category == small[0].category } ? small[0].category : .other
                siblings.append(.rollup(parent: parent, bytes: small.reduce(0) { $0 + $1.bytes },
                                        count: small.reduce(0) { $0 + $1.fileCount }, suffix: "pixels", category: category))
                siblings.sort(by: ordered)
            }
            let rectangles = squarify(siblings.map { Double($0.bytes) }, in: rect)
            for (node, tileRect) in zip(siblings, rectangles) {
                guard tileRect.width > 0, tileRect.height > 0 else { continue }
                let childBytes = node.children.reduce(Int64(0)) { $0 + $1.bytes }
                if !node.children.isEmpty, childBytes == node.bytes,
                   Double(tileRect.width * tileRect.height) >= minimum * 2 {
                    groups.append(TreemapGroup(node: node, rect: tileRect, depth: depth))
                    visit(node.children, rect: tileRect, depth: depth + 1)
                } else {
                    tiles.append(TreemapTile(node: node, rect: tileRect, depth: depth))
                }
            }
        }
        visit(nodes, rect: bounds, depth: 0)
        return TreemapResult(tiles: tiles, groups: groups)
    }

    private static func ordered(_ lhs: TreemapNode, _ rhs: TreemapNode) -> Bool {
        lhs.bytes == rhs.bytes ? lhs.id < rhs.id : lhs.bytes > rhs.bytes
    }

    private static func commonParent(_ paths: [String]) -> String {
        guard let first = paths.first else { return "/" }
        var parent = (first as NSString).deletingLastPathComponent
        for path in paths.dropFirst() {
            while parent != "/", path != parent, !path.hasPrefix(parent + "/") {
                let next = (parent as NSString).deletingLastPathComponent
                if next == parent || next.isEmpty { return "/" }
                parent = next
            }
        }
        return parent.isEmpty ? "/" : parent
    }

    private static func squarify(_ weights: [Double], in bounds: CGRect) -> [CGRect] {
        let total = weights.reduce(0, +)
        guard total > 0 else { return [] }
        // Normalize to unit area first; this avoids multiplication by a large Int64
        // allocation and keeps geometry independent of the unit used for byte values.
        let areas = weights.map { ($0 / total) * Double(bounds.width * bounds.height) }
        var remaining = bounds
        var result: [CGRect] = []
        var start = 0

        func worst(sum: Double, smallest: Double, largest: Double, side: Double) -> Double {
            guard sum > 0, smallest > 0, side > 0 else { return .infinity }
            let squared = side * side
            return max(squared * largest / (sum * sum), sum * sum / (squared * smallest))
        }
        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            var sum = areas[start]
            var score = worst(sum: sum, smallest: areas[start], largest: areas[start], side: side)
            while end < areas.count {
                let next = sum + areas[end]
                let nextScore = worst(sum: next, smallest: areas[end], largest: areas[start], side: side)
                if nextScore > score { break }
                sum = next; score = nextScore; end += 1
            }
            let finalRow = end == areas.count
            if remaining.width >= remaining.height {
                let width = finalRow ? remaining.width : min(remaining.width, CGFloat(sum / Double(remaining.height)))
                var y = remaining.minY
                for i in start..<end {
                    let height = i == end - 1 ? remaining.maxY - y : min(remaining.maxY - y, CGFloat(areas[i] / Double(width)))
                    result.append(CGRect(x: remaining.minX, y: y, width: width, height: max(0, height)))
                    y += height
                }
                remaining = CGRect(x: remaining.minX + width, y: remaining.minY,
                                   width: max(0, remaining.width - width), height: remaining.height)
            } else {
                let height = finalRow ? remaining.height : min(remaining.height, CGFloat(sum / Double(remaining.width)))
                var x = remaining.minX
                for i in start..<end {
                    let width = i == end - 1 ? remaining.maxX - x : min(remaining.maxX - x, CGFloat(areas[i] / Double(height)))
                    result.append(CGRect(x: x, y: remaining.minY, width: max(0, width), height: height))
                    x += width
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + height,
                                   width: remaining.width, height: max(0, remaining.height - height))
            }
            start = end
        }
        return result
    }
}
