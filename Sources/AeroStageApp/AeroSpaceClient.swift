import AeroStageCore
import Foundation

enum AeroSpaceError: Error, CustomStringConvertible {
    case commandFailed([String], String)

    var description: String {
        switch self {
        case let .commandFailed(args, stderr): "aerospace \(args.joined(separator: " ")): \(stderr)"
        }
    }
}

/// Thin layer over the `aerospace` CLI.
struct AeroSpaceClient: Sendable {
    let executable: String

    func run(_ args: [String]) async throws -> Data {
        let executable = executable
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw AeroSpaceError.commandFailed(args, String(decoding: errData, as: UTF8.self))
            }
            return data
        }.value
    }

    private func decode<T: Decodable>(_ type: T.Type, _ args: [String]) async throws -> T {
        try JSONDecoder().decode(type, from: try await run(args))
    }

    func windows() async throws -> [AeroWindow] {
        try await decode([AeroWindow].self, ["list-windows", "--all", "--json", "--format", AeroWindow.listFormat])
    }

    func monitors() async throws -> [AeroMonitor] {
        try await decode([AeroMonitor].self, ["list-monitors", "--json", "--format", AeroMonitor.listFormat])
    }

    func visibleWorkspaces() async throws -> [AeroWorkspaceRef] {
        try await decode([AeroWorkspaceRef].self,
                         ["list-workspaces", "--monitor", "all", "--visible", "--json", "--format", AeroWorkspaceRef.listFormat])
    }

    func focusedWorkspace() async throws -> String {
        String(decoding: try await run(["list-workspaces", "--focused"]), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func workspace(_ name: String) async throws {
        _ = try await run(["workspace", name])
    }

    func focus(windowId: Int) async throws {
        _ = try await run(["focus", "--window-id", String(windowId)])
    }

    func moveWindow(_ windowId: Int? = nil, to workspace: String, follow: Bool = false) async throws {
        var args = ["move-node-to-workspace"]
        if follow { args.append("--focus-follows-window") }
        if let windowId { args += ["--window-id", String(windowId)] }
        args.append(workspace)
        _ = try await run(args)
    }

    /// Puts a window back into the tiling tree (no-op if it is tiled already).
    func tile(windowId: Int) async throws {
        _ = try await run(["layout", "tiling", "--window-id", String(windowId)])
    }

    /// Makes a window float or puts it back into the tiling tree.
    func setFloating(_ floating: Bool, windowId: Int) async throws {
        _ = try await run(["layout", floating ? "floating" : "tiling", "--window-id", String(windowId)])
    }

    /// Arranges a whole workspace: `tiles` (side by side) or `accordion`.
    func setLayout(_ layout: String, workspace: String) async throws {
        _ = try await run(["layout", "--workspace", workspace, "--root", layout])
    }

    /// Undoes nested splits and arranges all windows of the workspace side by side again.
    func resetLayout(workspace: String) async throws {
        _ = try await run(["flatten-workspace-tree", "--workspace", workspace])
        try await setLayout("tiles", workspace: workspace)
    }

    func close(windowId: Int) async throws {
        _ = try await run(["close", "--window-id", String(windowId)])
    }

    func reloadConfig() async throws {
        _ = try await run(["reload-config"])
    }
}
