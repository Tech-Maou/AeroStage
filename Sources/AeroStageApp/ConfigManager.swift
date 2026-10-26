import AeroStageCore
import Foundation

/// Keeps the managed sections of the AeroSpace config up to date.
@MainActor
final class ConfigManager: ObservableObject {
    @Published private(set) var status = "Not checked yet"
    /// `start-at-login` in the AeroSpace config; `nil` if unknown or missing.
    @Published private(set) var aerospaceStartsAtLogin: Bool?

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
              var updated = ManagedConfig.replacingBlock(ManagedConfig.stagesBlock, in: withGaps, with: ManagedConfig.stagesBody(input.bindings))
        else {
            status = "AeroStage markers missing in \(url.path), config left unchanged"
            lastApplied = input
            return
        }
        // Optional: configs created before v0.3 have no bindings section.
        let bindings = ManagedConfig.bindingsBody(modifier: input.bindings.modifier)
        let hasBindings = ManagedConfig.replacingBlock(ManagedConfig.bindingsBlock, in: updated, with: bindings).map {
            updated = $0
            return true
        } ?? false

        lastApplied = input
        guard updated != original || !exists else {
            status = hasBindings ? "Up to date" : "Up to date (no bindings section, modifier only applies to stage shortcuts)"
            return
        }

        do {
            let backup = url.appendingPathExtension("aerostage-backup")
            if exists, !fm.fileExists(atPath: backup.path) {
                try fm.copyItem(at: url, to: backup)
            }
            try updated.write(to: url, atomically: true, encoding: .utf8)
            try? await client.reloadConfig()
            status = "Updated \(Date().formatted(date: .omitted, time: .standard))" + (hasBindings ? "" : " (no bindings section)")
        } catch {
            status = "Write failed: \(error.localizedDescription)"
        }
    }

    func readAeroSpaceStartAtLogin() {
        let text = try? String(contentsOf: configURL, encoding: .utf8)
        aerospaceStartsAtLogin = text.flatMap { ManagedConfig.boolSetting("start-at-login", in: $0) }
    }

    /// Writes `start-at-login` into the AeroSpace config; AeroSpace registers itself on reload.
    func setAeroSpaceStartAtLogin(_ enabled: Bool, client: AeroSpaceClient) async {
        let url = configURL
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let updated = ManagedConfig.settingBool("start-at-login", to: enabled, in: text)
        else {
            status = "start-at-login not found in \(url.path)"
            return
        }
        do {
            try updated.write(to: url, atomically: true, encoding: .utf8)
            try? await client.reloadConfig()
            status = "Updated start-at-login"
        } catch {
            status = "Write failed: \(error.localizedDescription)"
        }
        readAeroSpaceStartAtLogin()
    }

    /// Forces a rewrite on the next `apply`.
    func invalidate() {
        lastApplied = nil
    }
}
