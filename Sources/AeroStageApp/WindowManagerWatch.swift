import AeroStageCore
import AppKit

/// Watches the window manager's process. When it quits without AeroStage asking it to, the
/// sidebar and the menu say so and offer to start it again; a notification tells the user why
/// all windows are suddenly on one screen.
@MainActor
final class WindowManagerWatch: ObservableObject {
    static let originalBundleID = "bobko.aerospace"

    @Published private(set) var isRunning = true

    private let store: StateStore
    /// Set while AeroStage itself quits the window manager (menu, update), so no warning appears.
    var expectingQuit = false
    private var timer: Timer?
    /// A quit only counts after this long, so an update or restart does not flash a warning.
    private static let grace: TimeInterval = 4
    private var missingSince: Date?

    init(store: StateStore) {
        self.store = store
        // Launch and terminate notifications are not posted for apps without a Dock icon
        // (LSUIElement) like the window managers, and observing `runningApplications` missed a
        // restart during an update. A look at the process list every second is cheap and reliable.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }

    }

    var usesAeroStageWM: Bool { AeroSpacePaths.reportsWindowChanges(store.client.executable) }
    var name: String { usesAeroStageWM ? "AeroStage WM" : "AeroSpace" }
    var bundleID: String { usesAeroStageWM ? UpdateComponent.windowManager.bundleID : Self.originalBundleID }

    var process: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }
    }

    private func update() {
        if process != nil {
            missingSince = nil
            if !isRunning {
                NSLog("AeroStage: \(name) is running again")
                isRunning = true
                expectingQuit = false
                store.scheduleRefresh(after: .milliseconds(300))
            }
            return
        }
        let since = missingSince ?? Date()
        missingSince = since
        guard isRunning, -since.timeIntervalSinceNow >= Self.grace else { return }
        isRunning = false
        NSLog("AeroStage: \(name) is not running")
        if !expectingQuit {
            Notifier.shared.post(id: "window-manager", title: "\(name) quit",
                                 body: "All windows are back on screen. Start \(name) from the sidebar or the menu bar to put them back on their stages.")
        }
        store.scheduleRefresh(after: .milliseconds(300))
    }

    func start() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSSound.beep()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
