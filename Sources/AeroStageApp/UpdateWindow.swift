import AeroStageCore
import AppKit
import SwiftUI

/// Lists the available updates with their release notes and installs them with Homebrew.
struct UpdateView: View {
    @ObservedObject var checker: UpdateChecker
    var install: () -> Void
    var close: () -> Void

    private var installable: [UpdateChecker.Update] { UpdateInstaller.installable(checker.updates) }
    private var isBlocked: Bool { checker.updates.contains(where: UpdateInstaller.isBlocked) }
    private var downloads: [UpdateChecker.Update] {
        checker.updates.filter { !UpdateInstaller.isInstalledWithHomebrew($0.component) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                Text(checker.updates.isEmpty ? "No updates" : "A new version is available")
                    .font(.title2.bold())
            }

            if checker.updates.isEmpty {
                Text(checker.lastError ?? "AeroStage and AeroStage WM are up to date.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(checker.updates) { update in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("\(update.component.title) \(update.release.version.description)").font(.headline)
                                    Text("installed: \(update.installed)").foregroundStyle(.secondary)
                                    Spacer()
                                    Link("Release Notes", destination: update.release.htmlURL)
                                }
                                Text(Self.notes(update.release.body))
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                // A scroll view has no useful ideal height; without a frame the window collapses it.
                .frame(height: 260)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))

                if isBlocked { AeroSpaceCaskNote() }
                Text(!installable.isEmpty
                     ? "AeroStage returns all windows to the screen, quits, updates with Homebrew and opens again. This takes about a minute."
                     : downloads.isEmpty ? "" : "Not installed with Homebrew: download the new version from the release page.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                if checker.updates.isEmpty {
                    Button("OK", action: close).keyboardShortcut(.defaultAction)
                } else {
                    Button("Later", action: close).keyboardShortcut(.cancelAction)
                    if !installable.isEmpty {
                        Button(installable.count < checker.updates.count ? "Update \(installable.map(\.component.title).joined(separator: ", ")) Now" : "Update Now", action: install)
                            .keyboardShortcut(.defaultAction)
                    } else if !downloads.isEmpty {
                        Button("Open Release Page") {
                            downloads.forEach { NSWorkspace.shared.open($0.release.htmlURL) }
                            close()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    /// Release notes are Markdown; lists and headings are shown as plain lines.
    private static func notes(_ body: String?) -> AttributedString {
        let text = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return AttributedString("No release notes.") }
        return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// Homebrew refuses to upgrade AeroStage WM while AeroSpace's cask is installed.
struct AeroSpaceCaskNote: View {
    private let command = "brew uninstall --cask aerospace"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("AeroSpace is installed with Homebrew and blocks updating AeroStage WM. Uninstall it first; ~/.aerospace.toml is kept.", systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(command).font(.callout.monospaced()).textSelection(.enabled)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
                .controlSize(.small)
            }
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }
}

@MainActor
final class UpdateWindowController {
    private var window: NSWindow?
    private let checker: UpdateChecker
    private let install: () -> Void

    init(checker: UpdateChecker, install: @escaping () -> Void) {
        self.checker = checker
        self.install = install
    }

    func show() {
        if window == nil {
            let view = UpdateView(checker: checker, install: { [weak self] in
                self?.window?.close()
                self?.install()
            }, close: { [weak self] in self?.window?.close() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Software Update"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
