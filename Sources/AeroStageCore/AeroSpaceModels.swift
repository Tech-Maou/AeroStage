import Foundation

/// A window from `aerospace list-windows --json --format …`.
public struct AeroWindow: Codable, Hashable, Sendable, Identifiable {
    public let windowId: Int
    public let appName: String
    public let appBundleId: String?
    public let windowTitle: String
    public let workspace: String
    public let monitorId: Int
    /// Layout of the window's parent container: "floating", "h_tiles", "v_accordion", … (AeroSpace 0.20+).
    public let windowLayout: String?

    public var id: Int { windowId }
    public var isFloating: Bool { windowLayout == "floating" }

    public init(windowId: Int, appName: String, appBundleId: String?, windowTitle: String, workspace: String, monitorId: Int,
                windowLayout: String? = nil) {
        self.windowId = windowId
        self.appName = appName
        self.appBundleId = appBundleId
        self.windowTitle = windowTitle
        self.workspace = workspace
        self.monitorId = monitorId
        self.windowLayout = windowLayout
    }

    enum CodingKeys: String, CodingKey {
        case windowId = "window-id"
        case appName = "app-name"
        case appBundleId = "app-bundle-id"
        case windowTitle = "window-title"
        case workspace
        case monitorId = "monitor-id"
        case windowLayout = "window-layout"
    }

    /// Format string matching the CodingKeys.
    public static let listFormat = "%{window-id} %{app-name} %{app-bundle-id} %{window-title} %{workspace} %{monitor-id} %{window-layout}"
}

/// A monitor from `aerospace list-monitors --json --format …`.
public struct AeroMonitor: Codable, Hashable, Sendable {
    public let monitorId: Int
    public let name: String
    /// 1-based index into `NSScreen.screens`.
    public let nsScreenIndex: Int?

    public init(monitorId: Int, name: String, nsScreenIndex: Int?) {
        self.monitorId = monitorId
        self.name = name
        self.nsScreenIndex = nsScreenIndex
    }

    enum CodingKeys: String, CodingKey {
        case monitorId = "monitor-id"
        case name = "monitor-name"
        case nsScreenIndex = "monitor-appkit-nsscreen-screens-id"
    }

    public static let listFormat = "%{monitor-id} %{monitor-name} %{monitor-appkit-nsscreen-screens-id}"
}

/// A workspace with its monitor from `aerospace list-workspaces --json --format …`.
public struct AeroWorkspaceRef: Codable, Hashable, Sendable {
    public let workspace: String
    public let monitorId: Int

    public init(workspace: String, monitorId: Int) {
        self.workspace = workspace
        self.monitorId = monitorId
    }

    enum CodingKeys: String, CodingKey {
        case workspace
        case monitorId = "monitor-id"
    }

    public static let listFormat = "%{workspace} %{monitor-id}"
}

/// A line from `aerospace subscribe`.
public struct AeroEvent: Decodable, Sendable, Equatable {
    public enum Kind: String, Sendable {
        case focusChanged = "focus-changed"
        case focusedMonitorChanged = "focused-monitor-changed"
        case focusedWorkspaceChanged = "focused-workspace-changed"
        case modeChanged = "mode-changed"
        case windowDetected = "window-detected"
        case bindingTriggered = "binding-triggered"
        /// AeroStage WM only: the windows of a workspace changed (opened, closed, minimized, moved).
        case workspaceWindowsChanged = "workspace-windows-changed"
    }

    public let event: String
    public let workspace: String?
    public let prevWorkspace: String?
    public let windowId: Int?
    public let monitorId: Int?
    public let windowIds: [Int]?

    public var kind: Kind? { Kind(rawValue: event) }

    enum CodingKeys: String, CodingKey {
        case event = "_event"
        case workspace, prevWorkspace, windowId, monitorId, windowIds
    }

    public static func decode(line: Data) -> AeroEvent? {
        try? JSONDecoder().decode(AeroEvent.self, from: line)
    }
}

/// Locations of the window manager CLI, in search order: AeroStage WM first (the fork
/// AeroStage is made for), the original AeroSpace as a fallback.
public enum AeroSpacePaths {
    public static let candidates = [
        "/Applications/AeroStage WM.app/Contents/Resources/bin/aerostage-wm",
        "/opt/homebrew/bin/aerostage-wm",
        "/usr/local/bin/aerostage-wm",
        "/opt/homebrew/bin/aerospace",
        "/usr/local/bin/aerospace",
    ]

    /// AeroStage WM reports closed, minimized and moved windows itself (`workspace-windows-changed`).
    public static func reportsWindowChanges(_ executable: String) -> Bool {
        (executable as NSString).lastPathComponent == "aerostage-wm"
    }

    public static func locate(preferred: String? = nil) -> String? {
        let fm = FileManager.default
        if let preferred, !preferred.isEmpty, fm.isExecutableFile(atPath: preferred) {
            return preferred
        }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }
}
