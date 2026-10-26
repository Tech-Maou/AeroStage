import AeroStageCore
import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: StateStore
    @ObservedObject var config: ConfigManager
    @ObservedObject var thumbnails: ThumbnailService
    @ObservedObject var loginItem: LoginItem

    private enum Tab: String, CaseIterable {
        case general = "General"
        case appearance = "Appearance"
        case keyboard = "Keyboard"
        case aerospace = "AeroSpace"
    }

    @State private var tab = Tab.general

    var body: some View {
        // Own tab bar instead of TabView, whose tabs are always centered on macOS.
        VStack(alignment: .leading, spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.horizontal, 20)
            .padding(.top, 14)

            switch tab {
            case .general: general
            case .appearance: appearance
            case .keyboard: keyboard
            case .aerospace: aerospace
            }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
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
                Toggle("Start the window manager at login", isOn: Binding(
                    get: { config.aerospaceStartsAtLogin ?? false },
                    set: { enabled in
                        let client = store.client
                        Task { await config.setAeroSpaceStartAtLogin(enabled, client: client) }
                    }))
                .disabled(config.aerospaceStartsAtLogin == nil)
            } header: {
                Text("Startup")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    if let error = loginItem.lastError { Text(error) }
                    if config.aerospaceStartsAtLogin == nil {
                        Text("start-at-login was not found in \(config.configURL.path).")
                    } else {
                        Text("Sets start-at-login in the window manager config (~/.aerospace.toml, used by AeroStage WM and AeroSpace).")
                    }
                }
                .foregroundStyle(.secondary)
            }
            .onAppear {
                loginItem.refresh()
                config.readAeroSpaceStartAtLogin()
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

    // MARK: AeroSpace

    private var aerospace: some View {
        Form {
            Section {
                Toggle("Manage config (gaps and shortcuts)", isOn: $settings.manageConfig)
                Stepper("Gap between windows: \(settings.innerGap) pt", value: $settings.innerGap, in: 0...40)
                Stepper("Gap to screen edge: \(settings.outerGap) pt", value: $settings.outerGap, in: 0...40)
                TextField("Path to window manager CLI", text: $settings.aerospacePath, prompt: Text("automatic: aerostage-wm, then aerospace"))
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isConnected ? "Connected" : "Not reachable")
                    Text("\(config.configURL.path): \(config.status)")
                }
                .foregroundStyle(.secondary)
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

    init(makeView: @escaping () -> SettingsView) {
        self.makeView = makeView
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeView()))
            window.title = "AeroStage Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
