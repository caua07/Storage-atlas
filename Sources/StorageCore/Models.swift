import Foundation

public enum StorageCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case development, applications, caches, archives, models, media, documents, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .development: "Development"
        case .applications: "Applications"
        case .caches: "Caches"
        case .archives: "Archives & installers"
        case .models: "Models & checkpoints"
        case .media: "Media"
        case .documents: "Documents"
        case .other: "Other files"
        }
    }
    public var symbol: String {
        switch self {
        case .development: "chevron.left.forwardslash.chevron.right"
        case .applications: "app"
        case .caches: "arrow.triangle.2.circlepath"
        case .archives: "archivebox"
        case .models: "cpu"
        case .media: "photo.on.rectangle"
        case .documents: "doc.text"
        case .other: "square.dashed"
        }
    }
}

public struct StorageEntry: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public let path: String
    public let parent: String
    public let name: String
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let fileCount: Int64
    public let modified: Date?
    public let category: StorageCategory
    public let ruleID: String?
    public let isRuleRoot: Bool
    public var url: URL { URL(fileURLWithPath: path) }
    public var rule: RecognitionRule? { RuleCatalog.rule(ruleID) }
    public func bytes(allocated: Bool) -> Int64 { allocated ? allocatedBytes : logicalBytes }
}

public struct CategoryTotal: Identifiable, Sendable {
    public let category: StorageCategory
    public let bytes: Int64
    public let count: Int64
    public var id: String { category.rawValue }
}

/// A page of the actual filesystem hierarchy, including zero-allocation records.
public struct TreePage: Sendable {
    public let entries: [StorageEntry]
    public let hasMore: Bool
    public init(entries: [StorageEntry], hasMore: Bool) { self.entries = entries; self.hasMore = hasMore }
}

/// Breakdown of descendant regular files. Folder aggregate rows are non-additive.
public struct ScopeComposition: Sendable {
    public let totals: [CategoryTotal]
    public let allocatedBytes: Int64
    public let fileCount: Int64
    public let classificationVersion: Int
    public var isMixed: Bool { totals.filter { $0.count > 0 }.count > 1 }
    public init(totals: [CategoryTotal], allocatedBytes: Int64, fileCount: Int64, classificationVersion: Int) {
        self.totals = totals; self.allocatedBytes = allocatedBytes
        self.fileCount = fileCount; self.classificationVersion = classificationVersion
    }
}

public enum ScanScopeKind: String, Codable, Sendable { case folder, global }

public struct ScanSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let root: String
    public let started: Date
    public var finished: Date?
    public var status: String
    public var fileCount: Int64
    public var logicalBytes: Int64
    public var allocatedBytes: Int64
    public var issueCount: Int
    public var scopeKind: ScanScopeKind = .folder
    /// Finishing the planned traversal does not imply complete disk attribution.
    public var traversalCompleted: Bool { status == "complete" }
    public var isPartial: Bool { !traversalCompleted || issueCount > 0 }
}

public struct MapChildren: Sendable {
    public let entries: [StorageEntry]
    public let remainderBytes: Int64
    /// Descendant regular-file count, rather than the number of collapsed folders.
    public let remainderCount: Int64
}

extension ScanSummary {
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(String.self, forKey: .id), root: try values.decode(String.self, forKey: .root), started: try values.decode(Date.self, forKey: .started), finished: try values.decodeIfPresent(Date.self, forKey: .finished), status: try values.decode(String.self, forKey: .status), fileCount: try values.decode(Int64.self, forKey: .fileCount), logicalBytes: try values.decode(Int64.self, forKey: .logicalBytes), allocatedBytes: try values.decode(Int64.self, forKey: .allocatedBytes), issueCount: try values.decode(Int.self, forKey: .issueCount), scopeKind: try values.decodeIfPresent(ScanScopeKind.self, forKey: .scopeKind) ?? .folder)
    }
}

public struct ScanIssue: Identifiable, Sendable {
    public let path: String
    public let message: String
    public var id: String { path + message }
}

public enum ScanPhase: String, Sendable {
    case enumerating, finalizing, savingIndex
}

public struct ScanProgress: Sendable {
    public let fileCount: Int64
    public let allocatedBytes: Int64
    public let currentPath: String
    public let issueCount: Int
    public var scanID: String? = nil
    public var phase: ScanPhase = .enumerating
}

public final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public func cancel() { lock.lock(); value = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

public struct VolumeCapacity: Sendable {
    public let name: String
    public let total: Int64
    public let free: Int64
    public let importantAvailable: Int64?
    public var used: Int64 { max(0, total - free) }
    public static func read(at url: URL) throws -> VolumeCapacity {
        let values = try url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return VolumeCapacity(name: values.volumeName ?? "Macintosh HD", total: Int64(values.volumeTotalCapacity ?? 0), free: Int64(values.volumeAvailableCapacity ?? 0), importantAvailable: values.volumeAvailableCapacityForImportantUsage)
    }
}

public struct SpacePlan: Sendable {
    public let installed: Double
    public let download: Double
    public let workspace: Double
    public let reserve: Double
    public let hypotheticalRecovery: Double
    public let available: Double
    public init(installed: Double, download: Double, workspace: Double, reserve: Double, hypotheticalRecovery: Double, available: Double) {
        self.installed = Self.valid(installed); self.download = Self.valid(download)
        self.workspace = Self.valid(workspace); self.reserve = Self.valid(reserve)
        self.hypotheticalRecovery = Self.valid(hypotheticalRecovery); self.available = Self.valid(available)
    }
    private static func valid(_ n: Double) -> Double { n.isFinite ? max(0, n) : 0 }
    public var required: Double { installed + download + workspace + reserve }
    public var projectedAvailable: Double { available + hypotheticalRecovery }
    public var headroom: Double { projectedAvailable - required }
    public var fits: Bool { headroom >= 0 }
}
