import Foundation
import Darwin

/// A projection is a verified firmlink: physical Data prefix -> familiar startup path.
public struct GlobalPathMapping: Sendable {
    public let relativePath: String
    public let namespacePath: String
    public init(relativePath: String, namespacePath: String) {
        self.relativePath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.namespacePath = URL(fileURLWithPath: namespacePath).standardizedFileURL.path
    }
}

public struct GlobalScanRoot: Sendable {
    public let url: URL
    public let namespacePath: String
    public let deviceID: Int32
    public let volumeID: String?
    public let excludedPaths: [String]
    public let mappings: [GlobalPathMapping]
    public init(url: URL, namespacePath: String, deviceID: Int32, volumeID: String? = nil, excludedPaths: [String] = [], mappings: [GlobalPathMapping] = []) {
        self.url = ScanEngine.canonicalURL(url)
        self.namespacePath = URL(fileURLWithPath: namespacePath).standardizedFileURL.path
        self.deviceID = deviceID; self.volumeID = volumeID
        self.excludedPaths = excludedPaths
        self.mappings = mappings.sorted { $0.relativePath.count > $1.relativePath.count }
    }
    public func projectedPath(for physical: String) -> String {
        let relative = physical == url.path ? "" : String(physical.dropFirst(url.path == "/" ? 1 : url.path.count + 1))
        for mapping in mappings where relative == mapping.relativePath || relative.hasPrefix(mapping.relativePath + "/") {
            let suffix = String(relative.dropFirst(mapping.relativePath.count))
            return mapping.namespacePath + suffix
        }
        return relative.isEmpty ? namespacePath : (namespacePath == "/" ? "/" : namespacePath + "/") + relative
    }
}

public struct GlobalScanPlan: Sendable {
    public let roots: [GlobalScanRoot]
    /// Read capacity once here. System/Data share a container; never sum their capacities.
    public let capacityURL: URL
    public let coverageNotes: [ScanIssue]
    public init(roots: [GlobalScanRoot], capacityURL: URL, coverageNotes: [ScanIssue] = []) {
        self.roots = roots; self.capacityURL = capacityURL; self.coverageNotes = coverageNotes
    }
    /// Read-only topology discovery. Refuse an unverified startup group instead of calling '/' global.
    public static func discoverStartup() throws -> GlobalScanPlan {
        let system = URL(fileURLWithPath: "/", isDirectory: true)
        let data = URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)
        let systemInfo = try diskInfo(system), dataInfo = try diskInfo(data)
        try validateStartupTopology(system: systemInfo, data: dataInfo)
        var systemStat = stat(), dataStat = stat()
        // The merged startup namespace can expose the same POSIX st_dev for both
        // APFS volumes. Their distinct physical identities were verified above.
        guard lstat(system.path, &systemStat) == 0, lstat(data.path, &dataStat) == 0,
              systemStat.st_mode & S_IFMT == S_IFDIR, dataStat.st_mode & S_IFMT == S_IFDIR else {
            throw IndexError(message: "Could not access the verified startup System and Data roots.")
        }
        let firmlinks = try String(contentsOfFile: "/usr/share/firmlinks", encoding: .utf8)
        var mappings: [GlobalPathMapping] = []
        for line in firmlinks.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
            guard fields.count == 2, fields[0].hasPrefix("/"), !fields[1].contains("..") else { continue }
            // /Volumes is deliberately omitted from both namespaces, including mounted images.
            if fields[0] == "/Volumes" { continue }
            mappings.append(GlobalPathMapping(relativePath: String(fields[1]), namespacePath: String(fields[0])))
        }
        guard mappings.contains(where: { $0.namespacePath == "/Users" }), mappings.contains(where: { $0.namespacePath == "/Applications" }) else {
            throw IndexError(message: "Startup firmlink topology was unavailable; a safe global scope could not be established.")
        }
        return GlobalScanPlan(roots: [
            GlobalScanRoot(url: system, namespacePath: "/", deviceID: systemStat.st_dev, volumeID: systemInfo["VolumeUUID"] as? String, excludedPaths: ["/System/Volumes", "/Volumes"] + mappings.map(\.namespacePath)),
            GlobalScanRoot(url: data, namespacePath: data.path, deviceID: dataStat.st_dev, volumeID: dataInfo["VolumeUUID"] as? String, excludedPaths: [data.path + "/Volumes"], mappings: mappings)
        ], capacityURL: data, coverageNotes: [
            ScanIssue(path: "/System/Volumes", message: "Scope includes startup System and Data only. Auxiliary APFS volumes, snapshots, mounted images, backups and other mounts are outside measured file allocation.")
        ])
    }
    /// Kept separate from traversal so merged-namespace topology is regression-tested
    /// without enumerating the machine or requiring artificial mounted volumes.
    static func validateStartupTopology(system: [String: Any], data: [String: Any]) throws {
        guard system["Internal"] as? Bool == true, data["Internal"] as? Bool == true,
              system["FilesystemType"] as? String == "apfs", data["FilesystemType"] as? String == "apfs",
              let group = system["APFSVolumeGroupID"] as? String, !group.isEmpty,
              group == data["APFSVolumeGroupID"] as? String,
              let container = system["APFSContainerReference"] as? String, !container.isEmpty,
              container == data["APFSContainerReference"] as? String,
              let systemDevice = system["DeviceIdentifier"] as? String, !systemDevice.isEmpty,
              let dataDevice = data["DeviceIdentifier"] as? String, !dataDevice.isEmpty, systemDevice != dataDevice,
              let systemVolume = system["VolumeUUID"] as? String, !systemVolume.isEmpty,
              let dataVolume = data["VolumeUUID"] as? String, !dataVolume.isEmpty, systemVolume != dataVolume else {
            throw IndexError(message: "Could not verify distinct startup System/Data volumes in the internal APFS volume group.")
        }
    }
    private static func diskInfo(_ url: URL) throws -> [String: Any] {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", url.path]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let result = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw IndexError(message: "Could not read startup volume topology.")
        }
        return result
    }
}
