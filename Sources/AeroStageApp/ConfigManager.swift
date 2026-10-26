import AeroStageCore
import Foundation

/// Keeps the managed sections of the AeroSpace config up to date.
@MainActor
final class ConfigManager: ObservableObject {
    @Published private(set) var status = "Not checked yet"

    struct Input: Equatable {
        var gaps: ManagedConfig.GapOptions
        var bindings: ManagedConfig.BindingOptions
    }

    private var lastApplied: Input?

    /// `~/.aerospace.toml`, or the XDG variant if only that one exists.
    var configURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let classic = home.appendingPathComponent(".aerospace.toml")
        let xdg = home.appendingPathComponent(".config/aerospace/aerospace.toml")
        if !FileManager.default.fileExists(atPath: classic.path), FileManager.default.fileExists(atPath: xdg.path) {
            return xdg
        }
        return classic
    }

    func apply(_ input: Input, client: AeroSpaceClient) async {
        guard input != lastApplied else { return }
        let url = configURL
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: url.path)

        let original: String
        do {
            original = exists ? try String(contentsOf: url, encoding: .utf8) : DefaultConfig.template
        } catch {
            status = "Config not readable: \(error.localizedDescription)"
            return
        }

        guard let withGaps = ManagedConfig.replacingBlock(ManagedConfig.gapsBlock, in: original, with: ManagedConfig.gapsBody(input.gaps)),
              let updated = ManagedConfig.replacingBlock(ManagedConfig.stagesBlock, in: withGaps, with: ManagedConfig.stagesBody(input.bindings))
        else {
            status = "AeroStage markers missing in \(url.path), config left unchanged"
            lastApplied = input
            return
        }

        lastApplied = input
        guard updated != original || !exists else {
            status = "Up to date"
            return
        }

        do {
            let backup = url.appendingPathExtension("aerostage-backup")
            if exists, !fm.fileExists(atPath: backup.path) {
                try fm.copyItem(at: url, to: backup)
            }
            try updated.write(to: url, atomically: true, encoding: .utf8)
            try? await client.reloadConfig()
            status = "Updated \(Date().formatted(date: .omitted, time: .standard))"
        } catch {
            status = "Write failed: \(error.localizedDescription)"
        }
    }

    /// Forces a rewrite on the next `apply`.
    func invalidate() {
        lastApplied = nil
    }
}
