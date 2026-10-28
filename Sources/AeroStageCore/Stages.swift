import Foundation

public enum SidebarSide: String, Codable, CaseIterable, Sendable {
    case left, right
}

/// Shortcut modifier presets for different keyboard layouts.
public enum KeyboardPreset: String, CaseIterable, Sendable {
    /// `alt`, exactly like AeroSpace's defaults. On US layouts alt+key only types rarely used characters.
    case us
    /// `ctrl-alt`, for layouts where alt+key types characters you need (German: @ [ ] { } | ~).
    case international
    case custom

    public static let modifiers = ["alt", "ctrl-alt", "cmd-alt", "ctrl-alt-cmd"]

    public var modifier: String? {
        switch self {
        case .us: "alt"
        case .international: "ctrl-alt"
        case .custom: nil
        }
    }

    public init(modifier: String) {
        self = Self.allCases.first { $0.modifier == modifier } ?? .custom
    }

    /// Keyboard layouts (TIS input source IDs) for which `alt` is a safe modifier.
    public static let usLayoutIDs: Set<String> = [
        "com.apple.keylayout.US", "com.apple.keylayout.ABC", "com.apple.keylayout.USExtended",
        "com.apple.keylayout.Dvorak", "com.apple.keylayout.Colemak",
    ]

    public static func suggested(forLayoutID id: String?) -> KeyboardPreset {
        id.map(usLayoutIDs.contains) == true ? .us : .international
    }
}

/// A stage as it appears in the sidebar.
public struct Stage: Identifiable, Hashable, Sendable {
    public let workspace: String
    public let position: Int
    public let windows: [AeroWindow]
    public let isFocused: Bool

    public var id: String { workspace }

    /// The number shown on the card: the gapless position, not the workspace name.
    public var label: String { String(position) }

    public init(workspace: String, position: Int, windows: [AeroWindow], isFocused: Bool) {
        self.workspace = workspace
        self.position = position
        self.windows = windows
        self.isFocused = isFocused
    }
}

/// Order of the stages: gapless positions like Stage Manager. Known workspaces keep their place,
/// new ones go to the end, and the user can reorder them. Workspace names never change.
public struct StageOrder: Equatable, Sendable {
    public private(set) var names: [String]

    public init(names: [String] = []) {
        self.names = names
    }

    /// Reconciles the order with the workspaces currently present.
    public mutating func reconcile(with present: some Sequence<String>) {
        let presentSet = Set(present)
        var kept = names.filter { presentSet.contains($0) }
        let known = Set(kept)
        kept += presentSet.subtracting(known).sorted(by: Self.numericLess)
        names = kept
    }

    /// Moves a stage to a 1-based position; the stages in between shift by one.
    public mutating func move(_ name: String, toPosition position: Int) {
        guard let from = names.firstIndex(of: name) else { return }
        names.remove(at: from)
        names.insert(name, at: min(max(position - 1, 0), names.count))
    }

    /// Workspace name at a 1-based position.
    public func name(atPosition position: Int) -> String? {
        names.indices.contains(position - 1) ? names[position - 1] : nil
    }

    public func position(of name: String) -> Int? {
        names.firstIndex(of: name).map { $0 + 1 }
    }

    /// Neighbor stage with wrap-around; `offset` = +1 for next, -1 for previous.
    public func neighbor(of name: String?, offset: Int) -> String? {
        guard !names.isEmpty else { return nil }
        guard let name, let index = names.firstIndex(of: name) else {
            return offset >= 0 ? names.first : names.last
        }
        let count = names.count
        return names[((index + offset) % count + count) % count]
    }

    /// Lowest number from 1 that no workspace uses yet (on any monitor).
    public static func nextFreeName(excluding used: Set<String>) -> String {
        var n = 1
        while used.contains(String(n)) { n += 1 }
        return String(n)
    }

    /// Numbers numerically, everything else alphabetically after them.
    public static func numericLess(_ a: String, _ b: String) -> Bool {
        switch (Int(a), Int(b)) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return a.localizedStandardCompare(b) == .orderedAscending
        }
    }
}

/// How many stage cards fit into the sidebar, and how tall their previews may be.
public enum StageCapacity {
    /// At least 3 stages; at most 9 because shortcuts only go up to `mod-9`.
    public static let limits = 3...9

    /// Number of cards that fit when previews may shrink down to `minContentHeight`.
    /// - Parameters:
    ///   - availableHeight: height for the cards alone (without padding and "New Stage").
    ///   - cardChrome: fixed part of a card (header, gaps, padding).
    public static func count(availableHeight: Double, cardChrome: Double, minContentHeight: Double, spacing: Double) -> Int {
        let perCard = cardChrome + minContentHeight + spacing
        guard perCard > 0 else { return limits.lowerBound }
        let fitting = Int(((availableHeight + spacing) / perCard).rounded(.down))
        return min(max(fitting, limits.lowerBound), limits.upperBound)
    }

    /// Preview height so that `count` cards fit, never larger than the natural height.
    public static func contentHeight(availableHeight: Double, count: Int, cardChrome: Double, naturalContentHeight: Double, spacing: Double) -> Double {
        guard count > 0 else { return naturalContentHeight }
        let n = Double(count)
        let perCard = (availableHeight - (n - 1) * spacing) / n - cardChrome
        return max(0, min(naturalContentHeight, perCard))
    }
}

/// Which stage each window was on, saved while the window manager runs. When it restarts, all
/// windows land on one workspace; AeroStage then moves them back. Window ids stay the same as long
/// as the windows stay open, so ids of windows closed in between simply find no match.
public struct StageSnapshot: Codable, Equatable, Sendable {
    /// Process of the window manager the snapshot was taken from; a different one means it restarted.
    public var pid: Int32
    public var focusedWorkspace: String?
    public var workspaces: [Int: String]
    public var floating: Set<Int>
    /// App per window: after a reboot, ids start over and may belong to other windows.
    public var apps: [Int: String]
    public var savedAt: Date

    public init(pid: Int32, focusedWorkspace: String?, windows: [AeroWindow], savedAt: Date = Date()) {
        self.pid = pid
        self.focusedWorkspace = focusedWorkspace
        self.savedAt = savedAt
        workspaces = Dictionary(windows.map { ($0.windowId, $0.workspace) }, uniquingKeysWith: { first, _ in first })
        apps = Dictionary(windows.map { ($0.windowId, $0.appName) }, uniquingKeysWith: { first, _ in first })
        floating = Set(windows.filter(\.isFloating).map(\.windowId))
    }

    public struct Restore: Equatable, Sendable {
        public var moves: [(windowId: Int, workspace: String)]
        public var floating: [Int]

        public static func == (lhs: Restore, rhs: Restore) -> Bool {
            lhs.moves.map(\.windowId) == rhs.moves.map(\.windowId)
                && lhs.moves.map(\.workspace) == rhs.moves.map(\.workspace)
                && lhs.floating == rhs.floating
        }

        public var isEmpty: Bool { moves.isEmpty && floating.isEmpty }
    }

    /// Moves that put the still open windows back on their stages, and windows to float again.
    public func restore(onto windows: [AeroWindow]) -> Restore {
        let sorted = windows.sorted { $0.windowId < $1.windowId }.filter { apps[$0.windowId] == $0.appName }
        let moves = sorted.compactMap { window -> (windowId: Int, workspace: String)? in
            guard let saved = workspaces[window.windowId], saved != window.workspace else { return nil }
            return (window.windowId, saved)
        }
        let floatAgain = sorted.filter { floating.contains($0.windowId) && !$0.isFloating }.map(\.windowId)
        return Restore(moves: moves, floating: floatAgain)
    }
}
