import AeroStageCore
import AppKit
import SwiftUI

/// Sections of the settings window, grouped by app.
enum SettingsSection: String, CaseIterable, Hashable {
    case stageGeneral, stageAppearance, stageMenuBar
    case wmGeneral, wmKeyboard, wmGaps, wmAdvanced

    static let aeroStage: [SettingsSection] = [.stageGeneral, .stageAppearance, .stageMenuBar]
    static let windowManager: [SettingsSection] = [.wmGeneral, .wmKeyboard, .wmGaps, .wmAdvanced]

    var title: String {
        switch self {
        case .stageGeneral, .wmGeneral: "General"
        case .stageAppearance: "Appearance"
        case .stageMenuBar: "Menu Bar"
        case .wmKeyboard: "Keyboard"
        case .wmGaps: "Gaps"
        case .wmAdvanced: "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .stageGeneral: "sidebar.right"
        case .stageAppearance: "paintpalette"
        case .stageMenuBar: "menubar.rectangle"
        case .wmGeneral: "macwindow.on.rectangle"
        case .wmKeyboard: "keyboard"
        case .wmGaps: "rectangle.split.3x1"
        case .wmAdvanced: "gearshape.2"
        }
    }
}

/// Which section the settings window shows; set when opening it from the menu bar.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var section: SettingsSection? = .stageGeneral
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: StateStore
    @ObservedObject var config: ConfigManager
    @ObservedObject var thumbnails: ThumbnailService
    @ObservedObject var loginItem: LoginItem
    @ObservedObject var navigation: SettingsNavigation

    private var usesAeroStageWM: Bool { AeroSpacePaths.reportsWindowChanges(store.client.executable) }
    /// "AeroStage WM (AeroSpace)" with the fork, "AeroSpace" with the original.
    private var windowManagerTitle: String { usesAeroStageWM ? "AeroStage WM (AeroSpace)" : "AeroSpace" }

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.section) {
                Section("AeroStage") {
                    ForEach(SettingsSection.aeroStage, id: \.self) { Label($0.title, systemImage: $0.symbol) }
                }
                Section(windowManagerTitle) {
                    ForEach(SettingsSection.windowManager, id: \.self) { Label($0.title, systemImage: $0.symbol) }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            switch navigation.section ?? .stageGeneral {
            case .stageGeneral: general
            case .stageAppearance: appearance
            case .stageMenuBar: menuBar
            case .wmGeneral: windowManagerGeneral
            case .wmKeyboard: keyboard
            case .wmGaps: gaps
            case .wmAdvanced: advanced
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .onAppear {
            loginItem.refresh()
            config.readAeroSpaceStartAtLogin()
        }
    }

    // MARK: General: mode, position, monitors, numbering

    private var general: some View {
        Form {
            Section {
                Toggle("Launch AeroStage at login", isOn: Binding(
                    get: { loginItem.isEnabled || loginItem.needsApproval },
                    set: { loginItem.setEnabled($0) }))
                if loginItem.needsApproval {
                    LabeledContent("Needs approval") {
                        Button("Open Login Items …") { loginItem.openLoginItemsSettings() }
                    }
                }
            } header: {
                Text("Startup")
            } footer: {
                if let error = loginItem.lastError { Text(error).foregroundStyle(.secondary) }
            }

            Section {
                Picker("Mode", selection: $settings.displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if settings.displayMode == .overlay {
                    Toggle("Show when the mouse touches the screen edge", isOn: $settings.edgeTrigger)
                    Picker("Delay", selection: $settings.revealDelay) {
                        ForEach(AppSettings.revealDelays, id: \.self) { delay in
                            Text(delay == 0 ? "None" : "\(Int(delay * 1000)) ms").tag(delay)
                        }
                    }
                    .disabled(!settings.edgeTrigger)
                }
            } header: {
                Text("Mode")
            } footer: {
                Text(settings.displayMode == .overlay
                     ? "The sidebar floats above your windows and hides when the mouse leaves it. Windows get the full screen width. \(settings.modifier)-s shows it too."
                     : "The sidebar is always visible and AeroSpace keeps its space free.")
                    .foregroundStyle(.secondary)
            }

            Section("Position and Size") {
                Picker("Side", selection: $settings.side) {
                    Text("Left").tag(SidebarSide.left)
                    Text("Right").tag(SidebarSide.right)
                }
                .pickerStyle(.segmented)
                LabeledContent("Width") {
                    HStack {
                        Slider(value: $settings.widthPercent, in: 3...20, step: 0.5)
                        Text("\(settings.widthPercent, specifier: "%.1f") %").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                Stepper("At least \(Int(settings.minWidth)) pt", value: $settings.minWidth, in: 60...400, step: 10)
                Stepper("At most \(Int(settings.maxWidth)) pt", value: $settings.maxWidth, in: 60...600, step: 10)
            }

            Section {
                ForEach(Array(settings.monitorPriority.enumerated()), id: \.offset) { index, entry in
                    HStack {
                        Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                        Text(MonitorResolver.displayName(entry))
                        if isConnected(entry) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Connected")
                        }
                        Spacer()
                        Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0)
                        Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index == settings.monitorPriority.count - 1)
                        Button { settings.monitorPriority.remove(at: index) } label: { Image(systemName: "minus.circle") }
                    }
                    .buttonStyle(.borderless)
                }
                Menu("Add Monitor") {
                    ForEach(addableEntries, id: \.self) { entry in
                        Button(MonitorResolver.displayName(entry)) { settings.monitorPriority.append(entry) }
                    }
                }
                .disabled(addableEntries.isEmpty)
            } header: {
                Text("Monitors")
            } footer: {
                Text("The sidebar appears on the first connected monitor in this list. Current: \(store.sidebarMonitor?.name ?? "none")")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Numbering", selection: $settings.numbering) {
                    Text("Dynamic (positions)").tag(NumberingMode.dynamic)
                    Text("Fixed (AeroSpace names)").tag(NumberingMode.fixed)
                }
            } header: {
                Text("Stages")
            } footer: {
                Text("Up to \(settings.maxStages) stages on this monitor. The number follows the monitor's height, the sidebar width and the view, between 3 and 9.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Appearance: cards and colors

    private var appearance: some View {
        Form {
            Section("Cards") {
                Picker("Cards show", selection: $settings.cardStyle) {
                    ForEach(CardStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if settings.cardStyle.usesThumbnails {
                    Picker("Refresh thumbnails", selection: $settings.thumbnailInterval) {
                        ForEach(AppSettings.thumbnailIntervals, id: \.self) { seconds in
                            Text(seconds == 0 ? "Only on changes" : "Every \(Int(seconds)) s").tag(seconds)
                        }
                    }
                    if thumbnails.access == .denied {
                        LabeledContent("Screen Recording") {
                            HStack {
                                Text("not allowed, showing icons").foregroundStyle(.secondary)
                                Button("Allow …") {
                                    thumbnails.requestAccess()
                                    thumbnails.openPrivacySettings()
                                }
                            }
                        }
                    }
                }
            }

            Section("Icons") {
                LabeledContent("Icon size") {
                    HStack {
                        Slider(value: $settings.iconScale, in: 0.6...1.6, step: 0.1)
                        Text("\(Int(settings.iconScale * 100)) %").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("Background") {
                ColorPicker("Color", selection: colorBinding(\.backgroundColor), supportsOpacity: false)
                LabeledContent("Opacity") {
                    HStack {
                        Slider(value: $settings.backgroundOpacity, in: 0...1, step: 0.05)
                        Text("\(Int(settings.backgroundOpacity * 100)) %").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("Blur what is behind the sidebar", isOn: $settings.backgroundBlur)
            }

            Section {
                ColorPicker("Color", selection: colorBinding(\.textColor), supportsOpacity: false)
                Stepper("Size: \(Int(settings.titleSize)) pt", value: $settings.titleSize, in: 10...24, step: 1)
                Button("Reset Appearance") {
                    settings.backgroundColor = .black
                    settings.backgroundOpacity = 0.3
                    settings.backgroundBlur = false
                    settings.textColor = .white
                    settings.titleSize = 14
                    settings.iconScale = 1
                }
            } header: {
                Text("Titles")
            } footer: {
                Text("Titles get a soft shadow so they stay readable on a transparent background.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Keyboard

    private var keyboard: some View {
        Form {
            Section {
                Picker("Shortcuts", selection: $settings.keyboardPreset) {
                    Text("US (alt, AeroSpace default)").tag(KeyboardPreset.us)
                    Text("International (ctrl-alt)").tag(KeyboardPreset.international)
                    Text("Custom").tag(KeyboardPreset.custom)
                }
                if settings.keyboardPreset == .custom {
                    Picker("Modifier", selection: $settings.modifier) {
                        ForEach(KeyboardPreset.modifiers, id: \.self) { Text($0).tag($0) }
                    }
                }
                LabeledContent("Examples") {
                    Text("\(settings.modifier)-1 stage 1 · \(settings.modifier)-h focus left · \(settings.modifier)-shift-1 move window")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current keyboard layout: \(KeyboardLayout.currentName ?? "unknown"), suggested: \(KeyboardLayout.suggestedPreset == .us ? "US" : "International").")
                    Text("On many non-US layouts alt+key types characters you need (German: @ [ ] { } | ~), so ctrl-alt is safer there. alt-tab is always used for next stage.")
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Menu bar

    private var menuBar: some View {
        Form {
            Section {
                Toggle("Show AeroStage in the menu bar", isOn: $settings.showMenuBarItem)
                Toggle("Show the number of the visible stage", isOn: $settings.showStageNumber)
                    .disabled(!settings.showMenuBarItem)
            } footer: {
                Text("The menu lists the stages and opens the settings of both apps. Without the icon, the settings are still in the sidebar's context menu.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Hide AeroStage WM's own menu bar item", isOn: $settings.hideWindowManagerMenuBarItem)
                    .disabled(!usesAeroStageWM)
            } footer: {
                Text(usesAeroStageWM
                     ? "AeroStage WM's item shows its internal workspace name, not the stage number. It stays visible while AeroStage WM lacks the Accessibility permission."
                     : "Only available with AeroStage WM.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Window manager

    private var windowManagerGeneral: some View {
        Form {
            Section {
                Toggle("Start \(usesAeroStageWM ? "AeroStage WM" : "AeroSpace") at login", isOn: Binding(
                    get: { config.aerospaceStartsAtLogin ?? false },
                    set: { enabled in
                        let client = store.client
                        Task { await config.setAeroSpaceStartAtLogin(enabled, client: client) }
                    }))
                .disabled(config.aerospaceStartsAtLogin == nil)
            } header: {
                Text("Startup")
            } footer: {
                Text(config.aerospaceStartsAtLogin == nil
                     ? "start-at-login was not found in \(config.configURL.path)."
                     : "Sets start-at-login in the window manager config.")
                    .foregroundStyle(.secondary)
            }
            Section("Status") {
                LabeledContent("Window manager", value: windowManagerTitle)
                LabeledContent("Connection", value: store.isConnected ? "Connected" : "Not reachable")
                LabeledContent("Closed and minimized windows",
                               value: usesAeroStageWM ? "Reported as events" : "Noticed by a fallback check")
                LabeledContent("Config file", value: config.configURL.path)
            }
            if !usesAeroStageWM {
                Section {
                    Text("AeroStage runs reliably only with AeroStage WM, a fork of AeroSpace that reports closed, minimized and moved windows.")
                    Link("About AeroStage WM", destination: URL(string: "https://github.com/Tech-Maou/AeroStage-WM")!)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var gaps: some View {
        Form {
            Section {
                Stepper("Between windows: \(settings.innerGap) pt", value: $settings.innerGap, in: 0...40)
                Stepper("To the screen edge: \(settings.outerGap) pt", value: $settings.outerGap, in: 0...40)
            } footer: {
                Text("Written to the managed gaps section of the config. In reserved mode the sidebar's space is added on its side.")
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.manageConfig)
        }
        .formStyle(.grouped)
    }

    private var advanced: some View {
        Form {
            Section {
                Toggle("Manage config (gaps and shortcuts)", isOn: $settings.manageConfig)
            } footer: {
                Text("AeroStage only writes between its markers in the config file. Turned off, gaps and shortcuts are left to you.")
                    .foregroundStyle(.secondary)
            }
            Section("Config file") {
                LabeledContent("Status", value: config.status)
                HStack {
                    Button("Open in Editor") { NSWorkspace.shared.open(config.configURL) }
                    Button("Reload") {
                        let client = store.client
                        Task { try? await client.reloadConfig() }
                    }
                }
            }
            Section {
                TextField("Path to window manager CLI", text: $settings.aerospacePath,
                          prompt: Text("automatic: aerostage-wm, then aerospace"))
            } footer: {
                Text("In use: \(store.client.executable)").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, NSColor>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: settings[keyPath: keyPath]) },
            set: { settings[keyPath: keyPath] = NSColor($0) }
        )
    }

    private var addableEntries: [String] {
        let candidates = NSScreen.screens.map { MonitorResolver.isBuiltin($0) ? MonitorResolver.builtinToken : $0.localizedName }
        return (candidates + [MonitorResolver.builtinToken]).reduce(into: []) { result, entry in
            if !result.contains(entry), !settings.monitorPriority.contains(entry) { result.append(entry) }
        }
    }

    private func isConnected(_ entry: String) -> Bool {
        NSScreen.screens.contains { MonitorResolver.matches(entry, $0) }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard settings.monitorPriority.indices.contains(target) else { return }
        settings.monitorPriority.swapAt(index, target)
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let makeView: () -> SettingsView
    let navigation = SettingsNavigation()

    init(makeView: @escaping (SettingsNavigation) -> SettingsView) {
        let navigation = self.navigation
        self.makeView = { makeView(navigation) }
    }

    func show(_ section: SettingsSection = .stageGeneral) {
        navigation.section = section
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeView()))
            window.title = "AeroStage Settings"
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 820, height: 600))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
