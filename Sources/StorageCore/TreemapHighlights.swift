import Foundation

public struct TreemapHighlights: Equatable, Sendable {
    public let leafPaths: Set<String>
    public let rollupIDs: Set<String>
}

/// Reduces indexed matches to the bounded visible frontier. Directory contexts
/// are memoized; files sharing a directory do not rebuild its ancestor chain.
/// Substring keys retain slices of existing paths rather than copying ancestors.
public enum TreemapHighlightProjection {
    public static func resolve(matchingPaths: Set<String>, leafPaths: Set<String>,
                               groupPaths: Set<String>, rollupIDsByParent: [String: Set<String>]) throws -> TreemapHighlights {
        try Task.checkCancellation()
        let leaves = Dictionary(uniqueKeysWithValues: leafPaths.map { ($0[...], $0) })
        let groups = Set(groupPaths.map { $0[...] })
        let rollups = Dictionary(uniqueKeysWithValues: rollupIDsByParent.map { ($0.key[...], $0.value) })
        struct Context {
            var leaf: String?
            var rollupIDs: Set<String> = []
        }
        var contexts: [Substring: Context] = [:]
        var appliedParents = Set<Substring>()
        var matchedLeaves = Set<String>(), matchedRollups = Set<String>()

        func parent(of path: Substring) -> Substring {
            guard let slash = path.lastIndex(of: "/"), slash != path.startIndex else { return "/"[...] }
            return path[..<slash]
        }
        func context(for path: Substring) throws -> Context {
            if let cached = contexts[path] { return cached }
            var chain: [Substring] = [], cursor = path
            var result = Context()
            while true {
                try Task.checkCancellation()
                if let cached = contexts[cursor] { result = cached; break }
                chain.append(cursor)
                if let leaf = leaves[cursor] { result.leaf = leaf; break }
                if cursor == "/" { break }
                cursor = parent(of: cursor)
            }
            for segment in chain.reversed() {
                if result.leaf == nil, let ids = rollups[segment] { result.rollupIDs.formUnion(ids) }
                contexts[segment] = result
            }
            return result
        }

        for value in matchingPaths {
            try Task.checkCancellation()
            let path = value[...]
            if let leaf = leaves[path] { matchedLeaves.insert(leaf); continue }
            // An exact expanded-folder match adds no separate tile area. Its
            // descendant matches are resolved independently, as in the map.
            if groups.contains(path) { continue }
            let parentPath = parent(of: path)
            if appliedParents.insert(parentPath).inserted {
                let placement = try context(for: parentPath)
                if let leaf = placement.leaf { matchedLeaves.insert(leaf) }
                else { matchedRollups.formUnion(placement.rollupIDs) }
            }
            // A matched real parent may itself own a rollup even though it is
            // neither a visible leaf nor an expanded group (notably the root).
            if let ids = rollups[path], try context(for: parentPath).leaf == nil {
                matchedRollups.formUnion(ids)
            }
        }
        return TreemapHighlights(leafPaths: matchedLeaves, rollupIDs: matchedRollups)
    }
}
