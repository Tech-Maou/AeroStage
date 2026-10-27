import AeroStageCore
import AppKit
import Combine

/// AeroStage's menu bar item: a monochrome sidebar glyph with the visible stage's number, and a
/// menu for stages, settings of both apps, view, mode and quitting.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let windowManagerBundleID = "io.github.tech-maou.AeroStageWM"

    private let store: StateStore
    private let settings: AppSettings
    private var item: NSStatusItem?
    private var subscriptions: Set<AnyCancellable> = []

    var openSettings: (SettingsSection) -> Void = { _ in }
    var focusWorkspace: (String) -> Void = { _ in }

    init(store: StateStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        super.init()
        store.$stages
            .sink { [weak self] _ in DispatchQueue.main.async { self?.update() } }
            .store(in: &subscriptions)
        settings.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] in self?.update() }
            .store(in: &subscriptions)
        update()
    }

    /// "AeroStage WM" with the fork, "AeroSpace" with the original.
    var windowManagerName: String {
        AeroSpacePaths.reportsWindowChanges(store.client.executable) ? "AeroStage WM" : "AeroSpace"
    }

    func update() {
        guard settings.showMenuBarItem else {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        if item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = Self.glyph
            item.button?.imagePosition = .imageLeading
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.item = item
        }
        let active = store.stages.first(where: \.isFocused)
        let number = settings.showStageNumber ? active.map { $0.label(for: settings.numbering) } ?? "" : ""
        item?.button?.attributedTitle = NSAttributedString(
            string: number.isEmpty ? "" : " \(number)",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)])
        item?.button?.toolTip = active.map { "AeroStage – Stage \($0.label(for: settings.numbering))" } ?? "AeroStage"
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if store.stages.isEmpty {
            menu.addItem(disabled: store.isConnected ? "No stages" : "\(windowManagerName) not reachable")
        }
        for stage in store.stages {
            let names = stage.windows.map(\.appName).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            let title = "\(stage.label(for: settings.numbering))  \(names.isEmpty ? "Empty" : names.joined(separator: ", "))"
            let entry = menu.addItem(title) { [weak self] in self?.focusWorkspace(stage.workspace) }
            entry.state = stage.isFocused ? .on : .off
        }

        menu.addItem(.separator())
        menu.addItem("AeroStage Settings …") { [weak self] in self?.openSettings(.stageGeneral) }
        menu.addItem("\(windowManagerName) Settings …") { [weak self] in self?.openSettings(.wmGeneral) }

        let view = NSMenu()
        for style in CardStyle.allCases {
            view.addItem(style.title) { [weak self] in self?.settings.cardStyle = style }.state = settings.cardStyle == style ? .on : .off
        }
        menu.addItem(submenu: view, title: "View")
        let mode = NSMenu()
        for displayMode in DisplayMode.allCases {
            mode.addItem(displayMode.title) { [weak self] in self?.settings.displayMode = displayMode }.state = settings.displayMode == displayMode ? .on : .off
        }
        menu.addItem(submenu: mode, title: "Mode")

        menu.addItem(.separator())
        menu.addItem("Quit AeroStage") { NSApp.terminate(nil) }
        if windowManagerName == "AeroStage WM" {
            menu.addItem("Quit AeroStage WM") { [weak self] in self?.quitWindowManager() }
            menu.addItem("Quit Both") { [weak self] in
                self?.quitWindowManager { NSApp.terminate(nil) }
            }
        }
    }

    /// Quits AeroStage WM without leaving windows behind. Windows of hidden stages are parked in a
    /// screen corner, and a plain `terminate()` skips the cleanup that brings them back. `enable off`
    /// first returns every window to the screen; then the window manager is terminated.
    func quitWindowManager(then completion: @escaping @MainActor () -> Void = {}) {
        let cli = store.client.executable
        Task.detached {
            let disable = Process()
            disable.executableURL = URL(fileURLWithPath: cli)
            disable.arguments = ["enable", "off"]
            try? disable.run()
            disable.waitUntilExit()
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                NSRunningApplication.runningApplications(withBundleIdentifier: Self.windowManagerBundleID)
                    .forEach { $0.terminate() }
                completion()
            }
        }
    }

    /// The sidebar as an outline: a window on the left, three stage cards on the right.
    private static let glyph: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 15), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let window = NSBezierPath(roundedRect: NSRect(x: 1, y: 1.5, width: 11.5, height: 12), xRadius: 2, yRadius: 2)
            window.lineWidth = 1.4
            window.stroke()
            NSBezierPath(rect: NSRect(x: 1.5, y: 2, width: 10.5, height: 2.2)).fill()
            for row in 0..<3 {
                NSBezierPath(roundedRect: NSRect(x: 14.5, y: 1.5 + CGFloat(row) * 4.4, width: 4.5, height: 3.4), xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}

/// Menu items with a closure instead of target/action.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}

private extension NSMenu {
    @discardableResult
    func addItem(_ title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title, handler: handler)
        addItem(item)
        return item
    }

    func addItem(disabled title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }

    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
