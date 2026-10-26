import AeroStageCore
import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let config = ConfigManager()
    private let server = CommandServer()
    private let thumbnails = ThumbnailService()
    private var store: StateStore!
    private var events: EventStream!
    private var sidebar: SidebarController!
    private var commands: StageCommands!
    private var settingsWindow: SettingsWindowController!
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance: if the socket already answers, AeroStage is running.
        if (try? IPC.send(IPCRequest(command: .status), timeout: 1)) != nil {
            NSLog("AeroStage is already running")
            NSApp.terminate(nil)
            return
        }

        settings.seedMonitorPriorityIfNeeded()
        let client = makeClient()
        store = StateStore(client: client, settings: settings)
        commands = StageCommands(store: store, settings: settings)
        sidebar = SidebarController(store: store, settings: settings, thumbnails: thumbnails, actions: makeActions())
        settingsWindow = SettingsWindowController { [unowned self] in
            SettingsView(settings: settings, store: store, config: config, thumbnails: thumbnails)
        }

        commands.toggleSidebar = { [unowned self] in settings.sidebarVisible.toggle() }
        commands.openSettings = { [unowned self] in settingsWindow.show() }
        commands.thumbnailStatus = { [unowned self] in
            let access = switch thumbnails.access {
            case .granted: "allowed"
            case .denied: "not allowed"
            case .unknown: "unchecked"
            }
            let running = thumbnails.isRunning ? "running" : "stopped"
            return "view: \(settings.cardStyle.title) (\(running)), screen recording \(access), \(thumbnails.images.count) images, \(thumbnails.frames.count) positions, last capture \(thumbnails.lastCapture.map { String(format: "%.1f s ago", -$0.timeIntervalSinceNow) } ?? "–")"
        }
        commands.reload = { [unowned self] in
            config.invalidate()
            store.scheduleRefresh(after: .zero)
        }

        startEvents(executable: client.executable)
        observeSystem()
        observeState()

        let commands = commands!
        do {
            try server.start { request in await commands.handle(request) }
        } catch {
            NSLog("AeroStage: socket unavailable: \(error)")
        }

        store.scheduleRefresh(after: .zero)
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
        events?.stop()
    }

    private func makeClient() -> AeroSpaceClient {
        AeroSpaceClient(executable: AeroSpacePaths.locate(preferred: settings.aerospacePath) ?? AeroSpacePaths.candidates[0])
    }

    private func makeActions() -> SidebarActions {
        SidebarActions(
            focusWorkspace: { [unowned self] name in run { try await $0.workspace(name) } },
            focusWindow: { [unowned self] id in run { try await $0.focus(windowId: id) } },
            openSettings: { [unowned self] in settingsWindow.show() },
            hideSidebar: { [unowned self] in settings.sidebarVisible = false },
            quit: { NSApp.terminate(nil) }
        )
    }

    private func run(_ action: @escaping @Sendable (AeroSpaceClient) async throws -> Void) {
        let client = store.client
        Task {
            do { try await action(client) } catch { NSLog("AeroStage: \(error)") }
            store.scheduleRefresh()
        }
    }

    private func startEvents(executable: String) {
        events?.stop()
        events = EventStream(executable: executable)
        events.onEvent = { [unowned self] in store.handle($0) }
        events.onConnectionChange = { [unowned self] connected in
            if connected { store.scheduleRefresh() }
        }
        events.start()
    }

    /// Events AeroSpace does not report: app terminated, monitors changed.
    private func observeSystem() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [unowned self] _ in
                store.scheduleRefresh(after: .milliseconds(150))
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [unowned self] _ in
                store.scheduleRefresh(after: .milliseconds(300))
                sidebar.layout(on: store.sidebarScreen)
            }
            .store(in: &subscriptions)
    }

    private func observeState() {
        // Settings: re-layout the sidebar, re-resolve the target monitor, update the config.
        settings.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [unowned self] in
                let path = AeroSpacePaths.locate(preferred: settings.aerospacePath) ?? store.client.executable
                if path != store.client.executable {
                    store.client = AeroSpaceClient(executable: path)
                    startEvents(executable: path)
                }
                store.resolveSidebarTarget()
                store.restage()
                sidebar.layout(on: store.sidebarScreen)
                applyConfig()
                updateThumbnails()
            }
            .store(in: &subscriptions)

        store.$stages
            .sink { [unowned self] _ in
                DispatchQueue.main.async { self.updateThumbnails() }
            }
            .store(in: &subscriptions)

        store.$sidebarScreen
            .removeDuplicates()
            .sink { [unowned self] screen in sidebar.layout(on: screen) }
            .store(in: &subscriptions)

        store.$sidebarMonitor
            .removeDuplicates()
            .sink { [unowned self] _ in
                // Evaluate after the value is set; @Published fires before.
                DispatchQueue.main.async { self.applyConfig() }
            }
            .store(in: &subscriptions)
    }

    /// Capture thumbnails only while they are shown. Active stage first.
    private func updateThumbnails() {
        guard settings.cardStyle.usesThumbnails, settings.sidebarVisible, let screen = store.sidebarScreen else {
            thumbnails.stop()
            return
        }
        thumbnails.interval = settings.thumbnailInterval > 0 ? .seconds(settings.thumbnailInterval) : nil
        thumbnails.targetWidth = sidebar.width(on: screen) * 2.5
        thumbnails.canvas = windowArea(on: screen)
        let stages = store.stages.sorted { $0.isFocused && !$1.isFocused }
        thumbnails.update(windowIDs: stages.flatMap { $0.windows.map(\.windowId) })
    }

    /// Area in which AeroSpace lays out windows: the monitor in CG coordinates minus the sidebar.
    private func windowArea(on screen: NSScreen) -> CGRect {
        var area = CGDisplayBounds(MonitorResolver.displayID(screen))
        let reserved = CGFloat(sidebar.reservedGap(on: screen))
        area.size.width -= reserved
        if settings.side == .left { area.origin.x += reserved }
        return area
    }

    private func applyConfig() {
        guard settings.manageConfig else { return }
        let screen = store.sidebarScreen
        let input = ConfigManager.Input(
            gaps: .init(
                inner: settings.innerGap,
                outer: settings.outerGap,
                sidebarMonitor: settings.sidebarVisible ? store.sidebarMonitor?.name : nil,
                side: settings.side,
                sidebarGap: screen.map { sidebar.reservedGap(on: $0) } ?? 0),
            bindings: .init(
                mode: settings.numbering,
                modifier: settings.modifier,
                maxStages: settings.maxStages,
                cliPath: Self.cliPath))
        let client = store.client
        Task { await config.apply(input, client: client) }
    }

    /// Inside the bundle at Contents/Helpers; when run from `.build`, right next to the app binary.
    static var cliPath: String {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/aerostage").path
        if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        return Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("aerostage").path
    }
}
