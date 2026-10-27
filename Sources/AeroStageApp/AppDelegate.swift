import AeroStageCore
import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let config = ConfigManager()
    private let server = CommandServer()
    private let thumbnails = ThumbnailService()
    private let dragState = WindowDragState()
    private let loginItem = LoginItem()
    private var dragTracker: WindowDragTracker!
    private var store: StateStore!
    private var events: EventStream!
    private var sidebar: SidebarController!
    private var commands: StageCommands!
    private var settingsWindow: SettingsWindowController!
    private var menuBar: MenuBarController!
    private var updates: UpdateChecker!
    private let conflict = AeroSpaceConflict()
    private var updateWindow: UpdateWindowController!
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance: if the socket already answers, AeroStage is running.
        if (try? IPC.send(IPCRequest(command: .status), timeout: 1)) != nil {
            NSLog("AeroStage is already running")
            NSApp.terminate(nil)
            return
        }

        // A sidebar without a Dock icon must not be quit by macOS under memory pressure.
        ProcessInfo.processInfo.disableAutomaticTermination("AeroStage shows the sidebar")
        ProcessInfo.processInfo.disableSuddenTermination()
        settings.seedMonitorPriorityIfNeeded()
        let client = makeClient()
        store = StateStore(client: client, settings: settings)
        commands = StageCommands(store: store, settings: settings)
        let actions = makeActions()
        sidebar = SidebarController(store: store, settings: settings, thumbnails: thumbnails, dragState: dragState, actions: actions)
        setUpWindowDragging(actions: actions)
        updates = UpdateChecker(settings: settings)
        settingsWindow = SettingsWindowController { [unowned self] navigation in
            SettingsView(settings: settings, store: store, config: config, thumbnails: thumbnails, loginItem: loginItem, updates: updates, conflict: conflict, navigation: navigation)
        }
        menuBar = MenuBarController(store: store, settings: settings, updates: updates, conflict: conflict)
        menuBar.openSettings = { [unowned self] in settingsWindow.show($0) }
        menuBar.focusWorkspace = { [unowned self] name in
            let client = store.client
            Task { try? await client.workspace(name) }
        }
        syncWindowManagerMenuBarItem()
        updates.install = { [unowned self] list in
            UpdateInstaller.install(list) { menuBar.quitWindowManager(then: $0) }
        }
        updateWindow = UpdateWindowController(checker: updates) { [unowned self] in
            updates.install(updates.updates)
        }
        updates.showUpdates = { [unowned self] in updateWindow.show() }
        menuBar.showUpdates = updates.showUpdates
        updates.start()

        commands.toggleSidebar = { [unowned self] in sidebar.toggle() }
        sidebar.onVisibilityChange = { [unowned self] _ in updateThumbnails() }
        sidebar.onMenuTrackingChange = { [unowned self] open in thumbnails.isPaused = open }
        commands.openSettings = { [unowned self] in settingsWindow.show() }
        commands.checkForUpdates = { [unowned self] in
            let updates = updates!
            Task { await updates.check(userInitiated: true) }
        }
        commands.thumbnailStatus = { [unowned self] in
            let access = switch thumbnails.access {
            case .granted: "allowed"
            case .denied: "not allowed"
            case .unknown: "unchecked"
            }
            let running = thumbnails.isRunning ? "running" : "stopped"
            return "view: \(settings.cardStyle.title) (\(running)), screen recording \(access), \(thumbnails.images.count) images, \(thumbnails.frames.count) positions, last capture \(thumbnails.lastCapture.map { String(format: "%.1f s ago", -$0.timeIntervalSinceNow) } ?? "–")"
        }
        commands.startupStatus = { [unowned self] in
            loginItem.refresh()
            let login = switch loginItem.status {
            case .enabled: "on"
            case .requiresApproval: "needs approval"
            case .notRegistered: "off"
            default: "not found"
            }
            config.readAeroSpaceStartAtLogin()
            let aerospace = config.aerospaceStartsAtLogin.map { $0 ? "on" : "off" } ?? "unknown"
            return "launch at login: \(login), AeroSpace start-at-login: \(aerospace)"
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
            focusWorkspace: { [unowned self] name in
                run(dismiss: true) { try await $0.workspace(name) }
            },
            focusWindow: { [unowned self] id in
                run(dismiss: true) { try await $0.focus(windowId: id) }
            },
            // A moved window is tiled so the target stage splits like any other stage;
            // otherwise a floating window would just cover the others.
            moveWindow: { [unowned self] id, workspace in
                run { try await $0.moveWindow(id, to: workspace); try? await $0.tile(windowId: id) }
            },
            moveWindowToCurrentStage: { [unowned self] id in
                guard let current = store.activeWorkspace else { return }
                run { try await $0.moveWindow(id, to: current); try? await $0.tile(windowId: id) }
            },
            moveWindowToNewStage: { [unowned self] id in
                guard let name = commands.newStageName() else { return NSSound.beep() }
                run { try await $0.moveWindow(id, to: name); try? await $0.tile(windowId: id) }
            },
            toggleFloating: { [unowned self] id in
                run { try await $0.toggleFloating(windowId: id) }
            },
            newStage: { [unowned self] in
                guard let name = commands.newStageName() else { return NSSound.beep() }
                run(dismiss: true) { try await $0.workspace(name) }
            },
            closeWindow: { [unowned self] id in
                run { try await $0.close(windowId: id) }
            },
            closeStage: { [unowned self] workspace in
                let ids = store.stages.first { $0.workspace == workspace }?.windows.map(\.windowId) ?? []
                run { client in
                    for id in ids { try? await client.close(windowId: id) }
                }
            },
            setStageLayout: { [unowned self] workspace, layout in
                run { try await $0.setLayout(layout, workspace: workspace) }
            },
            resetStageLayout: { [unowned self] workspace in
                run { try await $0.resetLayout(workspace: workspace) }
            },
            canAddStage: { [unowned self] in commands.newStageName() != nil },
            openSettings: { [unowned self] in settingsWindow.show() },
            hideSidebar: { [unowned self] in settings.sidebarVisible = false },
            quit: { NSApp.terminate(nil) }
        )
    }

    /// Grab a real window and drop it onto a stage card or "New Stage" in the sidebar.
    private func setUpWindowDragging(actions: SidebarActions) {
        dragTracker = WindowDragTracker(
            state: dragState,
            panelFrame: { [unowned self] in sidebar.visibleFrame },
            isManaged: { [unowned self] in store.manages(windowId: $0) })
        dragTracker.onDragMove = { [unowned self] in sidebar.windowDragMoved(to: $0) }
        dragTracker.onDragEnd = { [unowned self] in sidebar.windowDragEnded() }
        dragTracker.onDrop = { [unowned self] id, target in
            // Let AeroSpace finish its own handling of the mouse-up first.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                switch target {
                case .stage(let workspace):
                    if store.workspace(ofWindow: id) != workspace { actions.moveWindow(id, workspace) }
                case .newStage:
                    actions.moveWindowToNewStage(id)
                }
            }
        }
        dragTracker.start()
    }

    /// Runs an AeroSpace command; `dismiss` hides the overlay afterwards (a stage or window was chosen).
    private func run(dismiss: Bool = false, _ action: @escaping @Sendable (AeroSpaceClient) async throws -> Void) {
        let client = store.client
        store.releaseHeldStage()
        if dismiss { sidebar.dismissOverlay() }
        Task {
            do { try await action(client) } catch { NSLog("AeroStage: \(error)") }
            store.scheduleRefresh()
        }
    }

    private func startEvents(executable: String) {
        events?.stop()
        events = EventStream(executable: executable)
        events.onEvent = { [unowned self] event in
            store.handle(event)
            // A stage chosen by keyboard while the overlay was opened by shortcut: get out of the way.
            if event.kind == .focusedWorkspaceChanged { sidebar.dismissOverlay() }
        }
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
            .sink { [unowned self] _ in screensMayHaveChanged() }
            .store(in: &subscriptions)

        // Docking usually happens behind the lock screen, where refreshes are skipped. Catch up
        // on unlock and wake, otherwise the sidebar keeps the previous monitor's position until
        // the next event (e.g. switching stages).
        DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.screenIsUnlocked"))
            .receive(on: RunLoop.main)
            .sink { [unowned self] _ in screensMayHaveChanged() }
            .store(in: &subscriptions)
        workspaceCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [unowned self] _ in screensMayHaveChanged() }
            .store(in: &subscriptions)
    }

    /// Picks the sidebar monitor from the current screens right away (no window manager call
    /// needed for the position) and refreshes the stages shortly after.
    private func screensMayHaveChanged() {
        store.resolveSidebarTarget()
        sidebar.layout(on: store.sidebarScreen)
        updateStageCapacity()
        store.scheduleRefresh(after: .milliseconds(300))
        // Screen configurations settle in steps; check once more.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            store.resolveSidebarTarget()
            sidebar.layout(on: store.sidebarScreen)
        }
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
                updateStageCapacity()
                syncWindowManagerMenuBarItem()
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
            .sink { [unowned self] screen in
                sidebar.layout(on: screen)
                DispatchQueue.main.async { self.updateStageCapacity() }
            }
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
        // A hidden overlay only captures on changes, so thumbnails are ready when it appears.
        let live = sidebar.isShown && settings.thumbnailInterval > 0
        let interval: Duration? = live ? .seconds(settings.thumbnailInterval) : nil
        if interval != thumbnails.interval || (sidebar.isShown && !thumbnails.isRunning) {
            thumbnails.interval = interval
            thumbnails.refreshNow()
        }
        thumbnails.targetWidth = sidebar.width(on: screen) * 2.5
        thumbnails.canvas = windowArea(on: screen)
        let stages = store.stages.sorted { $0.isFocused && !$1.isFocused }
        thumbnails.update(windowIDs: stages.flatMap { $0.windows.map(\.windowId) })
    }

    /// AeroStage WM hides its own menu bar item when told so through its user defaults.
    private func syncWindowManagerMenuBarItem() {
        let hide = settings.hideWindowManagerMenuBarItem && settings.showMenuBarItem
        let defaults = UserDefaults(suiteName: MenuBarController.windowManagerBundleID)
        if defaults?.object(forKey: "hideMenuBarItem") as? Bool != hide {
            defaults?.set(hide, forKey: "hideMenuBarItem")
        }
    }

    /// The stage limit follows the sidebar monitor: as many cards as fit at ≥ 70 % preview size.
    private func updateStageCapacity() {
        guard let screen = store.sidebarScreen else { return }
        let style = settings.cardStyle.usesThumbnails && thumbnails.access == .denied ? .icons : settings.cardStyle
        let area = windowArea(on: screen)
        let metrics = CardMetrics(panelSize: sidebar.panelSize(on: screen), style: style,
                                  titleSize: settings.titleSize, iconScale: settings.iconScale,
                                  canvasAspect: area.height > 0 ? area.width / area.height : 16 / 9)
        if metrics.capacity != settings.maxStages {
            settings.maxStages = metrics.capacity
        }
    }

    /// Area in which AeroSpace lays out windows: the monitor in CG coordinates, minus the
    /// sidebar in reserved mode.
    private func windowArea(on screen: NSScreen) -> CGRect {
        var area = CGDisplayBounds(MonitorResolver.displayID(screen))
        // Only reserved mode takes space away; in overlay mode windows use the full width.
        guard settings.displayMode == .reserved, settings.sidebarVisible else { return area }
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
                sidebarMonitor: settings.sidebarVisible && settings.displayMode == .reserved ? store.sidebarMonitor?.name : nil,
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
