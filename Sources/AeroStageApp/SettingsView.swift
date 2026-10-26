import AeroStageCore
import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: StateStore
    @ObservedObject var config: ConfigManager
    @ObservedObject var thumbnails: ThumbnailService

    var body: some View {
        Form {
            Section("Appearance") {
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

            Section("Stages") {
                Picker("Numbering", selection: $settings.numbering) {
                    Text("Dynamic (positions)").tag(NumberingMode.dynamic)
                    Text("Fixed (AeroSpace names)").tag(NumberingMode.fixed)
                }
                Picker("Maximum", selection: $settings.maxStages) {
                    ForEach(AppSettings.stageLimits, id: \.self) { Text("\($0)").tag($0) }
                }
            }

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
            } header: {
                Text("Keyboard")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current keyboard layout: \(KeyboardLayout.currentName ?? "unknown"), suggested: \(KeyboardLayout.suggestedPreset == .us ? "US" : "International").")
                    Text("On many non-US layouts alt+key types characters you need (German: @ [ ] { } | ~), so ctrl-alt is safer there. alt-tab is always used for next stage.")
                }
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Manage config (gaps and shortcuts)", isOn: $settings.manageConfig)
                Stepper("Gap between windows: \(settings.innerGap) pt", value: $settings.innerGap, in: 0...40)
                Stepper("Gap to screen edge: \(settings.outerGap) pt", value: $settings.outerGap, in: 0...40)
                TextField("Path to aerospace CLI", text: $settings.aerospacePath, prompt: Text("automatic"))
            } header: {
                Text("AeroSpace")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isConnected ? "Connected" : "Not reachable")
                    Text("\(config.configURL.path): \(config.status)")
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
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
