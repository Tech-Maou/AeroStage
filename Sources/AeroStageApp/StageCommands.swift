import AeroStageCore
import AppKit

/// Translates CLI commands (positions) into AeroSpace commands (workspace names).
@MainActor
final class StageCommands {
    private let store: StateStore
    private let settings: AppSettings
    var toggleSidebar: () -> Void = {}
    var openSettings: () -> Void = {}
    var reload: () -> Void = {}
    var thumbnailStatus: () -> String = { "" }

    init(store: StateStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    func handle(_ request: IPCRequest) async -> IPCResponse {
        do {
            let response = try await execute(request)
            store.scheduleRefresh()
            return response
        } catch {
            return .failure(String(describing: error))
        }
    }

    private func execute(_ request: IPCRequest) async throws -> IPCResponse {
        let client = store.client
        switch request.command {
        case .focus:
            guard let target = try target(at: request.position) else { return .success }
            try await client.workspace(target)
        case .move:
            guard let target = try target(at: request.position) else { return .success }
            try await client.moveWindow(to: target)
        case .new:
            guard store.stages.count < settings.maxStages else {
                return .failure("At most \(settings.maxStages) stages")
            }
            try await client.moveWindow(to: newStageName(), follow: true)
        case .next, .prev:
            let offset = request.command == .next ? 1 : -1
            if let target = store.order.neighbor(of: store.activeWorkspace, offset: offset),
               target != store.activeWorkspace {
                try await client.workspace(target)
            }
        case .toggle:
            toggleSidebar()
        case .settings:
            openSettings()
        case .reload:
            reload()
        case .quit:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                NSApp.terminate(nil)
            }
        case .status:
            return IPCResponse(ok: store.isConnected, message: status)
        }
        return .success
    }

    /// Workspace for a position. Position = count + 1 means: new stage.
    private func target(at position: Int?) throws -> String? {
        guard let position, position >= 1 else { throw CommandError("Missing position") }
        if let name = store.order.name(atPosition: position) { return name }
        guard position == store.stages.count + 1, store.stages.count < settings.maxStages else {
            NSSound.beep()
            return nil
        }
        return newStageName()
    }

    private func newStageName() -> String {
        settings.numbering == .fixed
            ? String(store.stages.count + 1)
            : StageOrder.nextFreeName(excluding: store.allWorkspaces)
    }

    private var status: String {
        let monitor = store.sidebarMonitor?.name ?? "no sidebar monitor"
        let stages = store.stages.map { "\($0.position)=\($0.workspace)" }.joined(separator: " ")
        return "AeroSpace \(store.isConnected ? "connected" : "not reachable"), \(monitor), stages: \(stages), \(thumbnailStatus())"
    }
}

struct CommandError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
