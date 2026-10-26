import AeroStageCore
import AppKit

/// Picks the sidebar monitor based on the priority list.
@MainActor
enum MonitorResolver {
    static let builtinToken = "@builtin"

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func isBuiltin(_ screen: NSScreen) -> Bool {
        CGDisplayIsBuiltin(displayID(screen)) != 0
    }

    static func matches(_ entry: String, _ screen: NSScreen) -> Bool {
        entry == builtinToken
            ? isBuiltin(screen)
            : screen.localizedName.localizedCaseInsensitiveContains(entry)
    }

    /// First connected monitor in the list; the built-in display is always the last resort.
    /// `nil` means: no sidebar (e.g. only a TV connected).
    static func resolveScreen(priority: [String]) -> NSScreen? {
        let screens = NSScreen.screens
        for entry in priority {
            if let screen = screens.first(where: { matches(entry, $0) }) { return screen }
        }
        if let builtin = screens.first(where: isBuiltin) { return builtin }
        return priority.isEmpty ? NSScreen.main : nil
    }

    /// Maps NSScreen → AeroSpace monitor via the NSScreen index, otherwise via the name.
    static func aeroMonitor(for screen: NSScreen, in monitors: [AeroMonitor]) -> AeroMonitor? {
        if let index = NSScreen.screens.firstIndex(of: screen),
           let monitor = monitors.first(where: { $0.nsScreenIndex == index + 1 }) {
            return monitor
        }
        return monitors.first { $0.name == screen.localizedName }
    }

    static func displayName(_ entry: String) -> String {
        entry == builtinToken ? "Built-in Display" : entry
    }
}
