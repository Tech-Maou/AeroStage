import Foundation

public enum NumberingMode: String, Codable, CaseIterable, Sendable {
    /// Gapless positions, new stages at the end, names picked by AeroStage.
    case dynamic
    /// The real AeroSpace names, gaps remain.
    case fixed
}

public enum SidebarSide: String, Codable, CaseIterable, Sendable {
    case left, right
}

/// A stage as it appears in the sidebar.
public struct Stage: Identifiable, Hashable, Sendable {
    public let workspace: String
    public let position: Int
    public let windows: [AeroWindow]
    public let isFocused: Bool

    public var id: String { workspace }

    /// The number shown on the card.
    public func label(for mode: NumberingMode) -> String {
        mode == .dynamic ? String(position) : workspace
    }

    public init(workspace: String, position: Int, windows: [AeroWindow], isFocused: Bool) {
        self.workspace = workspace
        self.position = position
        self.windows = windows
        self.isFocused = isFocused
    }
}

/// Order of the stages. Known workspaces keep their place, new ones go to the end.
public struct StageOrder: Equatable, Sendable {
    public private(set) var names: [String]

    public init(names: [String] = []) {
        self.names = names
    }

    /// Reconciles the order with the workspaces currently present.
    public mutating func reconcile(with present: some Sequence<String>, mode: NumberingMode) {
        let presentSet = Set(present)
        switch mode {
        case .fixed:
            names = presentSet.sorted(by: Self.numericLess)
        case .dynamic:
            var kept = names.filter { presentSet.contains($0) }
            let known = Set(kept)
            kept += presentSet.subtracting(known).sorted(by: Self.numericLess)
            names = kept
        }
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
