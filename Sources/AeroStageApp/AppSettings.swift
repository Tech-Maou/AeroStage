import AeroStageCore
import AppKit

enum CardStyle: String, CaseIterable {
    /// Thumbnails stacked like in Stage Manager.
    case thumbnails
    /// Thumbnails in their actual arrangement on screen.
    case layout
    case icons

    var title: String {
        switch self {
        case .thumbnails: "Stacked Thumbnails"
        case .layout: "Thumbnails in Layout"
        case .icons: "App-Icons"
        }
    }

    var usesThumbnails: Bool { self != .icons }
}

enum DisplayMode: String, CaseIterable {
    /// Always visible, AeroSpace reserves its space.
    case reserved
    /// Hidden until the mouse touches the screen edge, then floats above the windows.
    case overlay

    var title: String {
        switch self {
        case .reserved: "Reserved (always visible)"
        case .overlay: "Overlay (show at screen edge)"
        }
    }
}

/// All settings, persisted in `UserDefaults`.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var side: SidebarSide { didSet { defaults.set(side.rawValue, forKey: "side") } }
    /// Width in percent of the monitor width, clamped by `minWidth`/`maxWidth` (points).
    @Published var widthPercent: Double { didSet { defaults.set(widthPercent, forKey: "widthPercent") } }
    @Published var minWidth: Double { didSet { defaults.set(minWidth, forKey: "minWidth") } }
    @Published var maxWidth: Double { didSet { defaults.set(maxWidth, forKey: "maxWidth") } }
    /// Monitor names in descending priority; `MonitorResolver.builtinToken` stands for the built-in display.
    @Published var monitorPriority: [String] { didSet { defaults.set(monitorPriority, forKey: "monitorPriority") } }
    @Published var numbering: NumberingMode { didSet { defaults.set(numbering.rawValue, forKey: "numbering") } }
    /// Fixed; more stages than this are not needed in practice.
    let maxStages = 5
    @Published var modifier: String { didSet { defaults.set(modifier, forKey: "modifier") } }
    @Published var manageConfig: Bool { didSet { defaults.set(manageConfig, forKey: "manageConfig") } }
    @Published var innerGap: Int { didSet { defaults.set(innerGap, forKey: "innerGap") } }
    @Published var outerGap: Int { didSet { defaults.set(outerGap, forKey: "outerGap") } }
    /// Empty = locate automatically.
    @Published var aerospacePath: String { didSet { defaults.set(aerospacePath, forKey: "aerospacePath") } }
    @Published var sidebarVisible: Bool { didSet { defaults.set(sidebarVisible, forKey: "sidebarVisible") } }
    @Published var displayMode: DisplayMode { didSet { defaults.set(displayMode.rawValue, forKey: "displayMode") } }
    @Published var edgeTrigger: Bool { didSet { defaults.set(edgeTrigger, forKey: "edgeTrigger") } }
    /// Seconds the mouse has to rest at the screen edge before the overlay appears.
    @Published var revealDelay: Double { didSet { defaults.set(revealDelay, forKey: "revealDelay") } }
    @Published var backgroundColor: NSColor { didSet { defaults.set(backgroundColor.storedString, forKey: "backgroundColor") } }
    /// 0 = fully transparent, 1 = solid.
    @Published var backgroundOpacity: Double { didSet { defaults.set(backgroundOpacity, forKey: "backgroundOpacity") } }
    @Published var backgroundBlur: Bool { didSet { defaults.set(backgroundBlur, forKey: "backgroundBlur") } }
    @Published var textColor: NSColor { didSet { defaults.set(textColor.storedString, forKey: "textColor") } }
    /// Point size of the stage titles; the number is a bit larger.
    @Published var titleSize: Double { didSet { defaults.set(titleSize, forKey: "titleSize") } }
    @Published var cardStyle: CardStyle { didSet { defaults.set(cardStyle.rawValue, forKey: "cardStyle") } }
    /// Seconds between live thumbnail refreshes; 0 = only on changes.
    @Published var thumbnailInterval: Double { didSet { defaults.set(thumbnailInterval, forKey: "thumbnailInterval") } }

    static let thumbnailIntervals: [Double] = [1, 2, 3, 5, 10, 0]
    static let revealDelays: [Double] = [0, 0.1, 0.2, 0.35, 0.5]

    init() {
        let d = defaults
        side = SidebarSide(rawValue: d.string(forKey: "side") ?? "") ?? .right
        widthPercent = d.object(forKey: "widthPercent") as? Double ?? 7
        minWidth = d.object(forKey: "minWidth") as? Double ?? 120
        maxWidth = d.object(forKey: "maxWidth") as? Double ?? 260
        monitorPriority = d.stringArray(forKey: "monitorPriority") ?? []
        numbering = NumberingMode(rawValue: d.string(forKey: "numbering") ?? "") ?? .dynamic
        // First launch: alt on US layouts like AeroSpace, ctrl-alt where alt+key types characters.
        modifier = d.string(forKey: "modifier") ?? KeyboardLayout.suggestedPreset.modifier ?? "ctrl-alt"
        manageConfig = d.object(forKey: "manageConfig") as? Bool ?? true
        innerGap = d.object(forKey: "innerGap") as? Int ?? 8
        outerGap = d.object(forKey: "outerGap") as? Int ?? 8
        aerospacePath = d.string(forKey: "aerospacePath") ?? ""
        sidebarVisible = d.object(forKey: "sidebarVisible") as? Bool ?? true
        displayMode = DisplayMode(rawValue: d.string(forKey: "displayMode") ?? "") ?? .overlay
        edgeTrigger = d.object(forKey: "edgeTrigger") as? Bool ?? true
        revealDelay = d.object(forKey: "revealDelay") as? Double ?? 0.1
        backgroundColor = NSColor(storedString: d.string(forKey: "backgroundColor")) ?? .black
        backgroundOpacity = d.object(forKey: "backgroundOpacity") as? Double ?? 0.3
        backgroundBlur = d.object(forKey: "backgroundBlur") as? Bool ?? false
        textColor = NSColor(storedString: d.string(forKey: "textColor")) ?? .white
        titleSize = d.object(forKey: "titleSize") as? Double ?? 14
        cardStyle = CardStyle(rawValue: d.string(forKey: "cardStyle") ?? "") ?? .thumbnails
        thumbnailInterval = d.object(forKey: "thumbnailInterval") as? Double ?? 3
    }

    /// On first launch: current main monitor first, then the built-in display.
    func seedMonitorPriorityIfNeeded() {
        guard defaults.stringArray(forKey: "monitorPriority") == nil else { return }
        var list: [String] = []
        if let main = NSScreen.main, !MonitorResolver.isBuiltin(main) {
            list.append(main.localizedName)
        }
        list.append(MonitorResolver.builtinToken)
        monitorPriority = list
    }

    var keyboardPreset: KeyboardPreset {
        get { KeyboardPreset(modifier: modifier) }
        set {
            if let preset = newValue.modifier {
                modifier = preset
            } else if keyboardPreset != .custom {
                // Custom starts from a modifier that no preset uses.
                modifier = "cmd-alt"
            }
        }
    }

    var stageOrder: [String] {
        get { defaults.stringArray(forKey: "stageOrder") ?? [] }
        set { defaults.set(newValue, forKey: "stageOrder") }
    }
}

extension NSColor {
    /// "r g b" in sRGB, 0…1.
    var storedString: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(format: "%.4f %.4f %.4f", color.redComponent, color.greenComponent, color.blueComponent)
    }

    convenience init?(storedString: String?) {
        let parts = storedString?.split(separator: " ").compactMap { Double($0) } ?? []
        guard parts.count == 3 else { return nil }
        self.init(srgbRed: parts[0], green: parts[1], blue: parts[2], alpha: 1)
    }
}
