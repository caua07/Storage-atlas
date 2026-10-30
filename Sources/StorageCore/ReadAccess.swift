import Foundation
import Darwin

/// Observed read capability, never a claim about the macOS Full Disk Access switch.
public enum ReadAccessState: String, Codable, Sendable {
    case available, restricted, unknown
}

public struct ReadAccessObservation: Codable, Sendable {
    public let state: ReadAccessState
    public let checkedAt: Date
    public let readableCount: Int
    public let deniedCount: Int
}

public enum ReadAccessCheck {
    public enum Outcome: Sendable { case readable, denied, missing, indeterminate }

    /// Opens directory handles only. No file content or directory entries are read.
    public static func probe(_ path: String) -> Outcome {
        if let directory = opendir(path) {
            closedir(directory)
            return .readable
        }
        switch errno {
        case EPERM, EACCES: return .denied
        case ENOENT: return .missing
        default: return .indeterminate
        }
    }

    public static func check(paths: [String], at date: Date = Date(),
                             probe: (String) -> Outcome = Self.probe) -> ReadAccessObservation {
        var readable = 0, denied = 0, uncertain = 0
        for path in Set(paths) {
            switch probe(path) {
            case .readable: readable += 1
            case .denied: denied += 1
            case .missing: break
            case .indeterminate: uncertain += 1
            }
        }
        let state: ReadAccessState = denied > 0 ? .restricted : readable > 0 && uncertain == 0 ? .available : .unknown
        return ReadAccessObservation(state: state, checkedAt: date, readableCount: readable, deniedCount: denied)
    }

    public static func protectedUserFolders(home: URL) -> [String] {
        ["Library/Safari", "Library/Mail", "Library/Messages"].map { home.appendingPathComponent($0).path }
    }
}

/// Persistence is informational. A fresh observation must gate the notice each session.
public struct ReadAccessPreferences {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults) { self.defaults = defaults }
    public var lastObservation: ReadAccessObservation? {
        guard let data = defaults.data(forKey: "readAccess.observation.v1") else { return nil }
        return try? JSONDecoder().decode(ReadAccessObservation.self, from: data)
    }
    public var noticeDismissed: Bool { defaults.bool(forKey: "readAccess.noticeDismissed.v1") }
    public func save(_ observation: ReadAccessObservation) {
        // Newly lost access deserves fresh notice, even if a previous restriction was dismissed.
        if lastObservation?.state == .available, observation.state == .restricted {
            defaults.set(false, forKey: "readAccess.noticeDismissed.v1")
        }
        if let data = try? JSONEncoder().encode(observation) {
            defaults.set(data, forKey: "readAccess.observation.v1")
        }
    }
    public func dismissNotice() { defaults.set(true, forKey: "readAccess.noticeDismissed.v1") }
    public static func shouldShowNotice(current: ReadAccessObservation?, dismissed: Bool) -> Bool {
        current?.state == .restricted && !dismissed
    }
}
