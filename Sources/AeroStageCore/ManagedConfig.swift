import Foundation

/// Generates and replaces the sections of `~/.aerospace.toml` managed by AeroStage.
///
/// A section lies between the lines `# >>> AeroStage: <name> …` and
/// `# <<< AeroStage: <name> …`. Everything outside belongs to the user and stays untouched.
public enum ManagedConfig {
    public static let gapsBlock = "gaps"
    public static let stagesBlock = "stages"
    public static let bindingsBlock = "bindings"

    public struct GapOptions: Equatable, Sendable {
        public var inner: Int
        public var outer: Int
        /// AeroSpace name of the sidebar monitor; `nil` = no sidebar, nothing reserved.
        public var sidebarMonitor: String?
        public var side: SidebarSide
        /// Total gap at the sidebar edge (sidebar width + margins).
        public var sidebarGap: Int

        public init(inner: Int, outer: Int, sidebarMonitor: String?, side: SidebarSide, sidebarGap: Int) {
            self.inner = inner
            self.outer = outer
            self.sidebarMonitor = sidebarMonitor
            self.side = side
            self.sidebarGap = sidebarGap
        }
    }

    public struct BindingOptions: Equatable, Sendable {
        public var mode: NumberingMode
        public var modifier: String
        public var maxStages: Int
        public var cliPath: String

        public init(mode: NumberingMode, modifier: String, maxStages: Int, cliPath: String) {
            self.mode = mode
            self.modifier = modifier
            self.maxStages = maxStages
            self.cliPath = cliPath
        }
    }

    /// Replaces the content of a section. `nil` if the markers are missing.
    public static func replacingBlock(_ block: String, in text: String, with body: [String]) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.contains(">>> AeroStage: \(block) ") }),
              let end = lines[(start + 1)...].firstIndex(where: { $0.contains("<<< AeroStage: \(block) ") })
        else { return nil }
        lines.replaceSubrange((start + 1)..<end, with: body)
        return lines.joined(separator: "\n")
    }

    public static func gapsBody(_ options: GapOptions) -> [String] {
        func edge(_ side: SidebarSide) -> String {
            guard let monitor = options.sidebarMonitor, side == options.side else { return String(options.outer) }
            return "[{ monitor.'\(monitorPattern(monitor))' = \(options.sidebarGap) }, \(options.outer)]"
        }
        return [
            "gaps.inner.horizontal = \(options.inner)",
            "gaps.inner.vertical =   \(options.inner)",
            "gaps.outer.left =       \(edge(.left))",
            "gaps.outer.bottom =     \(options.outer)",
            "gaps.outer.top =        \(options.outer)",
            "gaps.outer.right =      \(edge(.right))",
        ]
    }

    /// AeroSpace's default main-mode shortcuts with the chosen modifier.
    public static func bindingsBody(modifier mod: String) -> [String] {
        [
            "    \(mod)-slash = 'layout tiles horizontal vertical'",
            "    \(mod)-comma = 'layout accordion horizontal vertical'",
            "",
            "    \(mod)-h = 'focus left'",
            "    \(mod)-j = 'focus down'",
            "    \(mod)-k = 'focus up'",
            "    \(mod)-l = 'focus right'",
            "",
            "    \(mod)-shift-h = 'move left'",
            "    \(mod)-shift-j = 'move down'",
            "    \(mod)-shift-k = 'move up'",
            "    \(mod)-shift-l = 'move right'",
            "",
            "    \(mod)-minus = 'resize smart -50'",
            "    \(mod)-equal = 'resize smart +50'",
            "",
            "    \(mod)-shift-semicolon = 'mode service'",
        ]
    }

    public static func stagesBody(_ options: BindingOptions) -> [String] {
        let mod = options.modifier
        let cli = "exec-and-forget \"\(options.cliPath)\""
        let range = 1...max(1, min(options.maxStages, 9))
        var lines: [String] = []
        switch options.mode {
        case .dynamic:
            lines.append("    # Dynamic: positions instead of names, translated by AeroStage")
            lines += range.map { "    \(mod)-\($0) = '\(cli) focus \($0)'" }
            lines.append("")
            lines += range.map { "    \(mod)-shift-\($0) = '\(cli) move \($0)'" }
        case .fixed:
            lines.append("    # Fixed: real AeroSpace workspace names")
            lines += range.map { "    \(mod)-\($0) = 'workspace \($0)'" }
            lines.append("")
            lines += range.map { "    \(mod)-shift-\($0) = 'move-node-to-workspace \($0)'" }
        }
        lines += [
            "",
            "    \(mod)-n = '\(cli) new'",
            "    alt-tab = '\(cli) next'",
            "    alt-shift-tab = '\(cli) prev'",
            "    \(mod)-s = '\(cli) toggle'",
        ]
        return lines
    }

    /// Value of a top-level boolean key such as `start-at-login`; `nil` if it is missing.
    public static func boolSetting(_ key: String, in text: String) -> Bool? {
        for line in text.components(separatedBy: "\n") {
            let parts = line.split(separator: "#", maxSplits: 1)[...].first.map { $0.split(separator: "=", maxSplits: 1) } ?? []
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key else { continue }
            switch parts[1].trimmingCharacters(in: .whitespaces) {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }
        return nil
    }

    /// Sets a top-level boolean key, keeping any comment on the line. `nil` if the key is missing.
    public static func settingBool(_ key: String, to value: Bool, in text: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: {
            $0.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) == key
        }) else { return nil }
        let comment = lines[index].range(of: "#").map { " " + lines[index][$0.lowerBound...] } ?? ""
        lines[index] = "\(key) = \(value)\(comment)"
        return lines.joined(separator: "\n")
    }

    /// AeroSpace monitor patterns are regular expressions; `'` is not allowed in a TOML literal key.
    public static func monitorPattern(_ name: String) -> String {
        NSRegularExpression.escapedPattern(for: name).replacingOccurrences(of: "'", with: ".")
    }
}
