import AeroStageCore
import AppKit
import Combine

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
    private var subscriptions: Set<AnyCancellable> = []

    init(store: StateStore) {
        self.store = store
        // Launch and terminate notifications are not posted for apps without a Dock icon
        // (LSUIElement) like the window managers, so observe the list of running apps instead.
        NSWorkspace.shared.publisher(for: \.runningApplications)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &subscriptions)
        isRunning = process != nil
    }

    var usesAeroStageWM: Bool { AeroSpacePaths.reportsWindowChanges(store.client.executable) }
    var name: String { usesAeroStageWM ? "AeroStage WM" : "AeroSpace" }
    var bundleID: String { usesAeroStageWM ? UpdateComponent.windowManager.bundleID : Self.originalBundleID }

    var process: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }
    }

    private func update() {
        let running = process != nil
        guard running != isRunning else { return }
        isRunning = running
        if !running && !expectingQuit {
            Notifier.shared.post(id: "window-manager", title: "\(name) quit",
                                 body: "All windows are back on screen. Start \(name) from the sidebar or the menu bar to put them back on their stages.")
        }
        if running { expectingQuit = false }
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
