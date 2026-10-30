import Foundation
import Darwin

/// Prevents a second process from opening a writer and interrupting the first scan.
public final class IndexProcessLock {
    private let descriptor: Int32
    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        descriptor = open(directory.appendingPathComponent("index-owner.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw IndexError(message: "Cannot create the Atlas index lock.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw IndexError(message: "Another Atlas process is already using this index. Close the other instance first.")
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

/// A selected update cannot prepare or install while a scan is running.
public struct UpdateInstallGate: Sendable {
    public private(set) var requested = false
    public private(set) var ready = false
    public private(set) var preparing = false
    public init() {}
    public mutating func request() { requested = true }
    public mutating func downloaded() { ready = true }
    public mutating func cancel() { self = Self() }
    public mutating func beginPreparation(scanRunning: Bool) -> Bool {
        guard requested, ready, !preparing, !scanRunning else { return false }
        preparing = true
        return true
    }
}
