import AeroStageCore
import AppKit
import Combine

/// The original AeroSpace next to AeroStage WM. Both read `~/.aerospace.toml`, so with
/// `start-at-login = true` both start at login and move the same windows. AeroStage warns
/// while both run and offers to quit AeroSpace.
@MainActor
final class AeroSpaceConflict: ObservableObject {
    static let bundleID = "bobko.aerospace"
    static let caskToken = "aerospace"

    @Published private(set) var bothRunning = false

    private var subscriptions: Set<AnyCancellable> = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.publisher(for: name)
                .sink { [weak self] _ in self?.update() }
                .store(in: &subscriptions)
        }
        // Checked after launch, so the alert does not appear before the sidebar.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.update() }
    }

    static var installedVersion: String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .flatMap { Bundle(url: $0) }?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Homebrew refuses to install or upgrade AeroStage WM while this cask is installed.
    static var isInstalledWithHomebrew: Bool { UpdateInstaller.isCaskInstalled(caskToken) }

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private func update() {
        let now = Self.isRunning(Self.bundleID) && Self.isRunning(UpdateComponent.windowManager.bundleID)
        guard now != bothRunning else { return }
        bothRunning = now
        if now { showAlert() }
    }

    private func showAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "AeroSpace and AeroStage WM are both running"
        alert.informativeText = """
            Both window managers move the same windows. Quit AeroSpace to let AeroStage WM work alone.

            Both read ~/.aerospace.toml, so AeroSpace starts at login again as long as it is installed. To switch for good, uninstall it: brew uninstall --cask aerospace, or move AeroSpace.app to the Trash.
            """
        alert.addButton(withTitle: "Quit AeroSpace")
        alert.addButton(withTitle: "Ignore")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { quitAeroSpace() }
    }

    /// AeroSpace leaves the windows of hidden workspaces parked in the screen corner when it is
    /// simply terminated, so `enable off` through its own CLI comes first.
    func quitAeroSpace() {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
        let pids = apps.map(\.processIdentifier)
        let cli = apps.compactMap { $0.bundleURL?.appendingPathComponent("Contents/Resources/bin/aerospace").path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        Task.detached {
            if let cli {
                let disable = Process()
                disable.executableURL = URL(fileURLWithPath: cli)
                disable.arguments = ["enable", "off"]
                try? disable.run()
                disable.waitUntilExit()
                try? await Task.sleep(for: .milliseconds(500))
            }
            await MainActor.run {
                pids.compactMap { NSRunningApplication(processIdentifier: $0) }.forEach { $0.terminate() }
            }
        }
    }
}
