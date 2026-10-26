import AeroStageCore
import AppKit

/// Single source of truth for the sidebar: stages, active stage, sidebar monitor.
///
/// Events trigger a debounced refresh via the CLI. A workspace change is shown
/// optimistically right away so the highlight moves without delay.
@MainActor
final class StateStore: ObservableObject {
    @Published private(set) var stages: [Stage] = []
    @Published private(set) var isConnected = false
    @Published private(set) var sidebarScreen: NSScreen?
    @Published private(set) var sidebarMonitor: AeroMonitor?

    /// All workspace names on all monitors (for picking new names).
    private(set) var allWorkspaces: Set<String> = []
    private(set) var order: StageOrder
    /// The workspace visible on the sidebar monitor.
    private(set) var activeWorkspace: String?

    var client: AeroSpaceClient
    private let settings: AppSettings
    private var windows: [AeroWindow] = []
    private var monitors: [AeroMonitor] = []
    private var visible: [AeroWorkspaceRef] = []
    /// Most recently focused window per workspace; shown in front of the stack.
    private var lastFocused: [String: Int] = [:]
    private var pendingRefresh: Task<Void, Never>?
    /// After leaving an emptied stage: hold this stage for a moment against macOS activating
    /// another app (AeroSpace would follow it to that app's stage).
    private var heldStage: (workspace: String, until: Date)?

    init(client: AeroSpaceClient, settings: AppSettings) {
        self.client = client
        self.settings = settings
        self.order = StageOrder(names: settings.stageOrder)
    }

    func handle(_ event: AeroEvent) {
        holdStageIfNeeded(event)
        if event.kind == .focusChanged, let workspace = event.workspace, let windowId = event.windowId {
            lastFocused[workspace] = windowId
        }
        if event.kind == .focusedWorkspaceChanged, let workspace = event.workspace,
           order.names.contains(workspace) {
            activeWorkspace = workspace
            restage()
        }
        scheduleRefresh()
    }

    func scheduleRefresh(after delay: Duration = .milliseconds(25)) {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func refresh() async {
        // Remember the active stage before the update to notice when it just became empty.
        let previousActive = activeWorkspace
        let previousOrder = order.names
        let previousWindowIDs = Set(windows.filter { $0.workspace == previousActive }.map(\.windowId))
        do {
            async let windows = client.windows()
            async let monitors = client.monitors()
            async let visible = client.visibleWorkspaces()
            let result = try await (windows, monitors, visible)
            guard !Task.isCancelled else { return }
            (self.windows, self.monitors, self.visible) = result
            isConnected = true
        } catch {
            guard !Task.isCancelled else { return }
            isConnected = false
            NSLog("AeroStage: refresh failed: \(error)")
        }
        allWorkspaces = Set(windows.map(\.workspace)).union(visible.map(\.workspace))
        resolveSidebarTarget()
        activeWorkspace = visible.first { $0.monitorId == sidebarMonitor?.monitorId }?.workspace
        restage()

        guard let emptied = previousActive, !previousWindowIDs.isEmpty,
              !windows.contains(where: { $0.workspace == emptied })
        else { return }
        // Closed or minimized: the windows are gone. macOS then activates some other app and
        // AeroSpace follows it to that app's stage, so AeroStage overrides that jump.
        // Moved away: only act if we are still on the empty stage (not when following the window).
        let closed = !windows.contains { previousWindowIDs.contains($0.windowId) }
        if closed || activeWorkspace == emptied {
            leaveEmptiedStage(emptied, previousOrder: previousOrder)
        }
    }

    /// The last window of the visible stage was closed, minimized or moved away: show the
    /// stage above it, or the next one if it was the first (like Stage Manager).
    private func leaveEmptiedStage(_ emptied: String, previousOrder: [String]) {
        guard let index = previousOrder.firstIndex(of: emptied) else { return }
        let remaining = Set(windows.map(\.workspace))
        let above = previousOrder[..<index].last { remaining.contains($0) }
        let below = previousOrder[(index + 1)...].first { remaining.contains($0) }
        guard let target = above ?? below else { return }
        heldStage = (target, Date().addingTimeInterval(2))
        let client = client
        Task { try? await client.workspace(target) }
    }

    /// The user did something on purpose (shortcut, click): stop holding the stage.
    func releaseHeldStage() {
        heldStage = nil
    }

    private func holdStageIfNeeded(_ event: AeroEvent) {
        guard let held = heldStage else { return }
        if event.kind == .bindingTriggered || Date() > held.until {
            heldStage = nil
            return
        }
        if event.kind == .focusedWorkspaceChanged, let workspace = event.workspace, workspace != held.workspace {
            let client = client
            Task { try? await client.workspace(held.workspace) }
        }
    }

    /// Whether AeroSpace manages this window (a dragged window has to be one of them).
    func manages(windowId: Int) -> Bool {
        windows.contains { $0.windowId == windowId }
    }

    /// Workspace a window currently lives on.
    func workspace(ofWindow windowId: Int) -> String? {
        windows.first { $0.windowId == windowId }?.workspace
    }

        /// After the priority list or the monitor setup changed.
    func resolveSidebarTarget() {
        let screen = MonitorResolver.resolveScreen(priority: settings.monitorPriority)
        let monitor = screen.flatMap { MonitorResolver.aeroMonitor(for: $0, in: monitors) }
        if screen != sidebarScreen { sidebarScreen = screen }
        if monitor != sidebarMonitor { sidebarMonitor = monitor }
    }

    /// Rebuilds the stage list from the last refresh.
    func restage() {
        guard let monitorId = sidebarMonitor?.monitorId else {
            if !stages.isEmpty { stages = [] }
            return
        }
        let byWorkspace = Dictionary(grouping: windows.filter { $0.monitorId == monitorId }, by: \.workspace)
        var present = Set(byWorkspace.keys)
        if let activeWorkspace { present.insert(activeWorkspace) }

        order.reconcile(with: present, mode: settings.numbering)
        if settings.numbering == .dynamic { settings.stageOrder = order.names }

        let newStages = order.names.enumerated().map { index, name in
            Stage(workspace: name, position: index + 1, windows: frontFirst(byWorkspace[name] ?? [], in: name), isFocused: name == activeWorkspace)
        }
        if newStages != stages { stages = newStages }
    }

    private func frontFirst(_ windows: [AeroWindow], in workspace: String) -> [AeroWindow] {
        guard let id = lastFocused[workspace], let index = windows.firstIndex(where: { $0.windowId == id }), index > 0 else {
            return windows
        }
        var result = windows
        result.insert(result.remove(at: index), at: 0)
        return result
    }
}
