import AppKit
import Combine
import SwiftUI
import Sparkle
import StorageCore

@MainActor final class UpdateController: NSObject, ObservableObject, SPUUserDriver, SPUUpdaterDelegate {
    @Published var title = "Updates"
    @Published var message = ""
    @Published var progress: Double?
    @Published var actionTitle: String?
    @Published var busy = false
    @Published var canCheck = false
    @Published var automaticChecks = UserDefaults.standard.object(forKey: "atlas.automaticUpdateChecks") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automaticChecks, forKey: "atlas.automaticUpdateChecks"); updater?.automaticallyChecksForUpdates = automaticChecks }
    }
    private weak var model: AppModel?
    private var updater: SPUUpdater?
    private var window: NSWindow?
    private var subscription: AnyCancellable?
    private var action: (() -> Void)?
    private var dismissAction: (() -> Void)?
    private var readyReply: ((SPUUserUpdateChoice) -> Void)?
    private var gate = UpdateInstallGate()
    private var received: UInt64 = 0
    private var expected: UInt64 = 0
    private var manual = false
    private var connected = false

    func connect(_ model: AppModel) {
        guard !connected else { return }; connected = true; self.model = model
        subscription = model.$isScanning.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor in self?.installWhenSafe() }
        }
        let channel = Bundle.main.object(forInfoDictionaryKey: "AtlasBuildChannel") as? String ?? "development"
        guard ["community", "distribution"].contains(channel) else { return }
        guard Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != nil else { return }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        self.updater = updater
        do {
            try updater.start()
            updater.automaticallyChecksForUpdates = automaticChecks
            updater.automaticallyDownloadsUpdates = false
            updater.sendsSystemProfile = false
            canCheck = true
            if automaticChecks { updater.checkForUpdatesInBackground() }
        } catch { displayError(error) }
    }
    func check() {
        guard let updater, updater.canCheckForUpdates else { return }
        manual = true; updater.checkForUpdates()
    }
    func performAction() { action?() }
    func dismiss() { dismissAction?(); dismissAction = nil; action = nil; window?.orderOut(nil) }
    private func present() {
        if window == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 270), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "Atlas Update"; panel.titlebarAppearsTransparent = true
            panel.contentView = NSHostingView(rootView: UpdateView(controller: self))
            panel.isReleasedWhenClosed = false; panel.center(); window = panel
        }
        window?.makeKeyAndOrderFront(nil)
    }
    private func displayError(_ error: Error) {
        model?.resumeAfterFailedUpdate()
        title = "Update could not finish"; message = error.localizedDescription
        busy = false; actionTitle = nil; action = nil; progress = nil; gate.cancel(); readyReply = nil
        dismissAction = nil; present()
    }
    private func installWhenSafe() {
        guard let model, let reply = readyReply else { return }
        guard gate.beginPreparation(scanRunning: model.isScanning) else {
            if model.isScanning { title = "Update ready"; message = "Your scan will finish before Atlas updates and restarts."; busy = true; progress = nil }
            return
        }
        title = "Installing update"; message = "Saving app state and restarting Atlas…"; busy = true
        Task {
            await model.prepareForUpdate()
            readyReply = nil
            reply(.install)
        }
    }
    private var installationProblem: String? {
        let path = Bundle.main.bundleURL.path
        if path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/") { return "Copy Atlas into Applications or your user Applications folder, then reopen it before updating." }
        guard FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            return "Atlas must be installed in a folder you own and can write to. Move it to your user Applications folder and reopen it."
        }
        return nil
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: automaticChecks, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        title = "Checking for updates"; message = "Checking the Atlas release feed…"; progress = nil; busy = true; actionTitle = nil; dismissAction = cancellation; present()
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        gate.cancel(); busy = false; progress = nil
        title = "Atlas \(appcastItem.displayVersionString) is available"
        message = "Install the latest version and restart. Your saved storage index and preferences stay on this Mac."
        actionTitle = model?.isScanning == true ? "Update after scan" : "Update and restart"
        dismissAction = { reply(.dismiss) }
        action = { [weak self] in
            guard let self else { return }
            if let problem = self.installationProblem { self.displayError(IndexError(message: problem)); reply(.dismiss); return }
            self.gate.request(); self.action = nil; self.actionTitle = nil; self.busy = true
            reply(.install)
        }
        present()
        if ProcessInfo.processInfo.arguments.contains("--verify-update-auto-install"), model?.isFixture == true {
            Task { try? await Task.sleep(for: .seconds(3)); self.performAction() }
        }
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        if manual { title = "Atlas is up to date"; message = "You’re using the newest compatible release."; busy = false; progress = nil; actionTitle = nil; present() }
        manual = false; acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        displayError(error); acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        received = 0; expected = 0; title = "Downloading update"; message = "The current app remains available until the update is verified."; busy = true; progress = nil; dismissAction = { [weak self] in self?.gate.cancel(); cancellation() }; present()
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { expected = expectedContentLength }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        received += length; progress = expected > 0 && received <= expected ? Double(received) / Double(expected) : nil
    }
    func showDownloadDidStartExtractingUpdate() { title = "Verifying update"; message = "Checking and preparing the signed update…"; progress = nil; dismissAction = nil }
    func showExtractionReceivedProgress(_ progress: Double) { self.progress = progress.isFinite ? min(1, max(0, progress)) : nil }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        gate.downloaded(); readyReply = reply; installWhenSafe()
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        title = "Installing update"; message = "Atlas will reopen automatically."; progress = nil; busy = true; present()
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement(); window?.orderOut(nil) }
    func dismissUpdateInstallation() { gate.cancel(); readyReply = nil; busy = false; action = nil; actionTitle = nil; dismissAction = nil; window?.orderOut(nil) }
    func showUpdateInFocus() { present() }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        Task {
            while model?.isScanning == true { try? await Task.sleep(for: .milliseconds(100)) }
            await model?.prepareForUpdate()
            installHandler()
        }
        return true
    }
}

private struct UpdateView: View {
    @ObservedObject var controller: UpdateController
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) { AtlasMark(); Text("Atlas Update").font(.system(size: 13, weight: .medium)).foregroundStyle(MapStyle.secondary) }
            Text(controller.title).font(.system(size: 21, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Text(controller.message).font(.system(size: 13)).foregroundStyle(MapStyle.secondary).fixedSize(horizontal: false, vertical: true)
            if controller.busy {
                if let progress = controller.progress { ProgressView(value: progress) } else { ProgressView().controlSize(.small) }
            }
            HStack {
                Button(controller.busy ? "Cancel" : "Later", action: controller.dismiss).buttonStyle(AtlasControlStyle())
                    .disabled(controller.busy && controller.title != "Downloading update" && controller.title != "Checking for updates")
                Spacer()
                if let title = controller.actionTitle { Button(title, action: controller.performAction).buttonStyle(AtlasNoticeActionStyle()).keyboardShortcut(.defaultAction) }
            }
        }.padding(24).frame(width: 440, alignment: .leading).frame(minHeight: 270)
            .foregroundStyle(MapStyle.text).background(MapStyle.panel).preferredColorScheme(.dark)
    }
}
