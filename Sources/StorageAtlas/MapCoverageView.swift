import AppKit
import SwiftUI
import StorageCore

/// Coverage remains a native popover: a readable account of measurement and its limits.
struct MapCoverageView: View {
    @EnvironmentObject private var model: AppModel
    private var prioritizedIssues: [ScanIssue] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return model.issues.sorted {
            let firstHome = StorageNavigation.contains($0.path, in: home)
            let secondHome = StorageNavigation.contains($1.path, in: home)
            return firstHome == secondHome ? $0.path < $1.path : firstHome
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Coverage & measurement")
                        .font(.system(size: 20, weight: .semibold))
                    if let scan = model.summary {
                        Text(scan.scopeKind == .global ? "Startup storage scan" : "Folder scan: \(shortPath(scan.root))")
                            .foregroundStyle(MapStyle.secondary)
                            .textSelection(.enabled)
                    }
                }

                    section("Storage read access") {
                        Text(readAccessStatus).fontWeight(.medium)
                        if let observation = model.readAccess {
                            Text("Checked \(observation.checkedAt.formatted(date: .abbreviated, time: .standard)) · \(observation.readableCount) readable · \(observation.deniedCount) restricted")
                                .foregroundStyle(MapStyle.secondary)
                        }
                        Text(model.readAccess?.state == .available
                             ? "Read access is available for the protected folders checked. Old scan notes remain historical; refresh to update the map. This check does not certify access to every file."
                             : "Atlas checks whether protected user folders can actually be opened. This does not read the macOS permission switch. Full Disk Access can help with denied folders; some restrictions can remain even when it is enabled.")
                            .foregroundStyle(MapStyle.secondary)
                        Button(model.isCheckingReadAccess ? "Checking…" : "Check read access again", action: model.checkReadAccess)
                            .disabled(model.isCheckingReadAccess).buttonStyle(.bordered).controlSize(.small)
                        HStack(spacing: 10) {
                            Button("Open Full Disk Access Settings", action: model.openFullDiskAccessSettings)
                            Button("Show this app in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                            }
                        }.buttonStyle(.bordered).controlSize(.small)
                        if model.readAccess?.state != .available {
                        Text("If access is denied: add or enable this copy in Full Disk Access. If already enabled, quit and reopen Atlas, then check again. Refresh (⌘R) after access changes to rebuild the map.")
                            .foregroundStyle(MapStyle.secondary)
                        }
                        Text(Bundle.main.bundleURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MapStyle.secondary).textSelection(.enabled)
                        Text("Some system restrictions can remain. Atlas stays read-only and never changes permissions itself.")
                            .foregroundStyle(MapStyle.secondary)
                    }

                if let scan = model.summary {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(byteString(scan.allocatedBytes))
                            .font(.system(size: 28, weight: .medium)).monospacedDigit()
                        Text("Mapped allocation · \(scan.fileCount.formatted()) files")
                            .foregroundStyle(MapStyle.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: scan.isPartial ? "exclamationmark.circle" : "info.circle")
                                .foregroundStyle(scan.isPartial ? MapStyle.warning : MapStyle.secondary)
                                .accessibilityHidden(true)
                            Text(model.statusLabel).fontWeight(.medium)
                        }
                        if scan.traversalCompleted, scan.issueCount > 0 {
                            Text("The scan finished. Coverage is limited by unreadable locations and exclusions recorded below. Scanning again without changing access may produce the same result.")
                                .foregroundStyle(MapStyle.secondary)
                        }
                        Text("Measured \((scan.finished ?? scan.started).formatted(date: .complete, time: .shortened))")
                            .foregroundStyle(MapStyle.secondary)
                    }
                }

                if let capacity = model.capacity {
                    section("Volume capacity") {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
                            capacityRow("Volume used", value: capacity.used)
                            capacityRow("Currently free", value: capacity.free)
                            capacityRow("Capacity", value: capacity.total)
                            if let scan = model.summary, scan.scopeKind == .global {
                                capacityRow("Mapped files", value: scan.allocatedBytes)
                                if capacity.used > scan.allocatedBytes {
                                    capacityRow("Difference · unattributed", value: capacity.used - scan.allocatedBytes)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let scan = model.summary, scan.scopeKind == .global, capacity.used > scan.allocatedBytes {
                            Text("The difference can include unreadable locations, excluded volumes or snapshots, filesystem overhead and accounting differences. Its breakdown has not been measured.")
                                .foregroundStyle(MapStyle.secondary)
                        }
                    }
                }

                section("What the map measures") {
                    Text("Tile area represents measured allocated bytes. Logical file length is shown separately in item details. Shared APFS blocks, compression, snapshots, and changing files prevent these numbers from describing exclusive recoverable space.")
                        .foregroundStyle(MapStyle.secondary)
                }

                section("Scope & exclusions") {
                    Text("Symbolic links are not followed. Unrelated mounted volumes, duplicate namespaces, and Atlas’s own index are excluded. Inaccessible locations have unknown sizes and are not filled into the map.")
                        .foregroundStyle(MapStyle.secondary)
                }

                section("Coverage notes") {
                    Text("\(model.issues.count.formatted()) retained · \((model.summary?.issueCount ?? model.issues.count).formatted()) recorded")
                        .foregroundStyle(MapStyle.secondary)
                    if let scan = model.summary, scan.issueCount > model.issues.count {
                        Text("Showing \(model.issues.count.formatted()) of \(scan.issueCount.formatted()) coverage notes. Interrupted scans may not have saved individual paths; refresh to rebuild them.")
                            .foregroundStyle(MapStyle.secondary)
                    }
                    if !model.issues.isEmpty {
                        Text("Retained locations · home-folder notes first")
                            .fontWeight(.medium)
                        ForEach(prioritizedIssues) { issue in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(shortPath(issue.path)).textSelection(.enabled)
                                Text(issue.message).foregroundStyle(MapStyle.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .font(.system(size: 12))
            .lineSpacing(3)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 480, height: 500)
        .foregroundStyle(MapStyle.text)
        .background(MapStyle.panel)
    }

    private var readAccessStatus: String {
        if model.isCheckingReadAccess { return "Checking current read access…" }
        switch model.readAccess?.state {
        case .available: return "Read access available for checked folders"
        case .restricted: return "Read access restricted for a checked folder"
        default: return "Read access could not be verified"
        }
    }

    private func capacityRow(_ label: String, value: Int64) -> some View {
        GridRow {
            Text(label).foregroundStyle(MapStyle.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(byteString(value)).monospacedDigit()
                .gridColumnAlignment(.trailing)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(MapStyle.line).frame(height: 1).padding(.bottom, 8)
            Text(title).font(.system(size: 13, weight: .semibold))
            content()
        }
    }
}
