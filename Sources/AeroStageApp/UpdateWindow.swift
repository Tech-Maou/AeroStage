import AeroStageCore
import AppKit
import SwiftUI

/// Lists the available updates with their release notes and installs them with Homebrew.
struct UpdateView: View {
    @ObservedObject var checker: UpdateChecker
    var install: () -> Void
    var close: () -> Void

    private var canInstall: Bool { UpdateInstaller.canInstall(checker.updates) }

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

                Text(canInstall
                     ? "AeroStage returns all windows to the screen, quits, updates with Homebrew and opens again. This takes about a minute."
                     : "Not installed with Homebrew: download the new version from the release page.")
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
                    if canInstall {
                        Button("Update Now", action: install).keyboardShortcut(.defaultAction)
                    } else {
                        Button("Open Release Page") {
                            checker.updates.forEach { NSWorkspace.shared.open($0.release.htmlURL) }
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
