import SwiftUI
import AppKit

@main struct StorageAtlasApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updates = UpdateController()
    @NSApplicationDelegateAdaptor(AtlasAppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("Storage Atlas") {
            WorkspaceView().environmentObject(model)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(.dark)
                .tint(MapStyle.text)
                .task { updates.connect(model); await NativeVerification.runIfRequested(model: model) }
        }
        .defaultSize(width: 1500, height: 940)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…", action: updates.check).disabled(!updates.canCheck)
                Toggle("Check for Updates on Launch", isOn: $updates.automaticChecks)
            }
            CommandGroup(replacing: .newItem) {
                Button("Refresh Internal Storage") { model.refreshGlobal() }.keyboardShortcut("r").disabled(model.isScanning)
            }
            CommandMenu("Map") {
                Button("Back") { model.goBack() }.keyboardShortcut("[").disabled(!model.canGoBack)
                Button("Forward") { model.goForward() }.keyboardShortcut("]").disabled(!model.canGoForward)
                Button("Folders") { model.togglePanel(.folders) }.keyboardShortcut("\\")
                Button("Search") { model.requestSearchFocus() }.keyboardShortcut("f")
                Button("Global View") { model.goGlobal() }.keyboardShortcut("0")
                Button("Enclosing Folder") { model.goUp() }.keyboardShortcut(.upArrow, modifiers: .command)
                Button("Largest Files") { model.togglePanel(.results) }.keyboardShortcut("l")
                Button("Item Details") { model.togglePanel(.details) }.keyboardShortcut("i")
                Button("Coverage") { model.showCoverage.toggle() }
                Button("Stop Scan") { model.cancelScan() }.disabled(!model.isScanning)
            }
        }
    }
}

final class AtlasAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
