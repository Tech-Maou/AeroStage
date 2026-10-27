import AeroStageCore
import AppKit
import SwiftUI

/// Sections of the settings window, grouped by app.
enum SettingsSection: String, CaseIterable, Hashable {
    case stageGeneral, stageAppearance, stageMenuBar
    case wmGeneral, wmKeyboard, wmLayout, wmGaps, wmBehavior, wmAdvanced

    static let aeroStage: [SettingsSection] = [.stageGeneral, .stageAppearance, .stageMenuBar]
    static let windowManager: [SettingsSection] = [.wmGeneral, .wmKeyboard, .wmLayout, .wmGaps, .wmBehavior, .wmAdvanced]

    var title: String {
        switch self {
        case .stageGeneral, .wmGeneral: "General"
        case .stageAppearance: "Appearance"
        case .stageMenuBar: "Menu Bar"
        case .wmKeyboard: "Keyboard"
        case .wmLayout: "Layout"
        case .wmGaps: "Gaps"
        case .wmBehavior: "Behavior"
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
        case .wmLayout: "rectangle.3.group"
        case .wmGaps: "rectangle.split.3x1"
        case .wmBehavior: "cursorarrow.motionlines"
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
    @ObservedObject var updates: UpdateChecker
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
            let section = navigation.section ?? .stageGeneral
            VStack(spacing: 0) {
                // Permanent on every window manager page while the original AeroSpace is used.
                if SettingsSection.windowManager.contains(section), !usesAeroStageWM {
                    AeroSpaceWarningBanner()
                }
                switch section {
                case .stageGeneral: general
                case .stageAppearance: appearance
                case .stageMenuBar: menuBar
                case .wmGeneral: windowManagerGeneral
                case .wmKeyboard: keyboard
                case .wmLayout: layout
                case .wmGaps: gaps
                case .wmBehavior: behavior
                case .wmAdvanced: advanced
                }
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .onAppear {
            loginItem.refresh()
            config.readAeroSpaceStartAtLogin()
            config.readValues()
        }
    }

    // MARK: Window manager config values

    private func configBool(_ key: String) -> Binding<Bool> {
        Binding(
            get: { config.values[key] == "true" },
            set: { value in write(key, String(value)) })
    }

    private func configString(_ key: String, default fallback: String) -> Binding<String> {
        Binding(
            get: { config.values[key].flatMap { ManagedConfig.stringSetting(key, in: "\(key) = \($0)") } ?? fallback },
            set: { value in write(key, "'\(value)'") })
    }

    private func configInt(_ key: String, default fallback: Int) -> Binding<Int> {
        Binding(
            get: { config.values[key].flatMap(Int.init) ?? fallback },
            set: { value in write(key, String(value)) })
    }

    private func write(_ key: String, _ raw: String) {
        let client = store.client
        Task { await config.setValue(key, raw: raw, client: client) }
    }

    private func missing(_ keys: String...) -> Bool {
        keys.contains { config.values[$0] == nil }
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
                Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
                LabeledContent("Status") {
                    HStack {
                        Text(updateStatus).foregroundStyle(.secondary)
                        if updates.isChecking { ProgressView().controlSize(.small) }
                        if !updates.updates.isEmpty {
                            Button("Show Update …") { updates.showUpdates() }
                        }
                        Button("Check Now") { Task { await updates.check(userInitiated: true) } }
                            .disabled(updates.isChecking)
                    }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Once a day, AeroStage asks GitHub for new releases of AeroStage and AeroStage WM. Updates are installed with Homebrew.")
                    .foregroundStyle(.secondary)
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
                Picker("Key positions", selection: configString("key-mapping.preset", default: "qwerty")) {
                    Text("QWERTY (also QWERTZ, AZERTY)").tag("qwerty")
                    Text("Dvorak").tag("dvorak")
                    Text("Colemak").tag("colemak")
                }
                .disabled(missing("key-mapping.preset"))
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
        }
        .formStyle(.grouped)
    }

    private var layout: some View {
        Form {
            Section {
                Picker("New stages", selection: configString("default-root-container-layout", default: "tiles")) {
                    Text("Side by side").tag("tiles")
                    Text("Accordion").tag("accordion")
                }
                Picker("Direction", selection: configString("default-root-container-orientation", default: "auto")) {
                    Text("Automatic (wide screens horizontal)").tag("auto")
                    Text("Horizontal").tag("horizontal")
                    Text("Vertical").tag("vertical")
                }
                Stepper("Accordion offset: \(configInt("accordion-padding", default: 30).wrappedValue) pt",
                        value: configInt("accordion-padding", default: 30), in: 0...100, step: 5)
            } header: {
                Text("Default layout")
            } footer: {
                Text("Applies to stages created from now on; existing stages keep their layout (change it from a stage's context menu). When the window manager starts with more than three windows on a stage, it arranges them as an accordion regardless.")
                    .foregroundStyle(.secondary)
            }
            .disabled(missing("default-root-container-layout", "default-root-container-orientation", "accordion-padding"))

            Section {
                Toggle("Flatten nested containers", isOn: configBool("enable-normalization-flatten-containers"))
                Toggle("Alternate direction of nested splits", isOn: configBool("enable-normalization-opposite-orientation-for-nested-containers"))
            } header: {
                Text("Normalization")
            } footer: {
                Text("Keeps the window tree tidy: containers with a single child are removed, and a split inside a split runs the other way. AeroSpace recommends leaving both on.")
                    .foregroundStyle(.secondary)
            }
            .disabled(missing("enable-normalization-flatten-containers", "enable-normalization-opposite-orientation-for-nested-containers"))
        }
        .formStyle(.grouped)
    }

    private var behavior: some View {
        Form {
            Section {
                Toggle("Focus follows the mouse", isOn: configBool("focus-follows-mouse.enabled"))
                    .disabled(missing("focus-follows-mouse.enabled"))
                Toggle("Move the mouse along when focusing another monitor", isOn: Binding(
                    get: { config.values["on-focused-monitor-changed"]?.contains("move-mouse") == true },
                    set: { write("on-focused-monitor-changed", $0 ? "['move-mouse monitor-lazy-center']" : "[]") }))
                    .disabled(missing("on-focused-monitor-changed"))
                Toggle("Show apps hidden with ⌘H again automatically", isOn: configBool("automatically-unhide-macos-hidden-apps"))
                    .disabled(missing("automatically-unhide-macos-hidden-apps"))
            } footer: {
                Text("Hiding apps with ⌘H doesn't fit tiling well; with the last option on, hidden apps come back right away.")
                    .foregroundStyle(.secondary)
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
                Toggle("Reload automatically when the file is saved", isOn: configBool("auto-reload-config"))
                    .disabled(missing("auto-reload-config"))
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

    private var updateStatus: String {
        if let error = updates.lastError { return error }
        if !updates.updates.isEmpty {
            return updates.updates.map { "\($0.component.title) \($0.release.version) available" }.joined(separator: ", ")
        }
        guard let last = updates.lastCheck else { return "Not checked yet" }
        return "Up to date, checked \(last.formatted(.relative(presentation: .named)))"
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

/// Shown above the window manager settings while the original AeroSpace is in use; cannot be dismissed.
struct AeroSpaceWarningBanner: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white, .orange)
                .font(.title3)
            (Text("Full functionality only with AeroStage WM. ").fontWeight(.semibold)
                + Text("With the original AeroSpace, closed, minimized and moved windows are only noticed by a fallback check, and some options are unavailable. ")
                + Text("[AeroStage WM on GitHub](https://github.com/Tech-Maou/AeroStage-WM)").underline())
                .tint(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.orange.opacity(0.8), lineWidth: 1))
        .padding([.horizontal, .top], 20)
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
