import AeroStageCore
import AppKit
@preconcurrency import UserNotifications

/// Asks GitHub once a day for the latest releases of AeroStage and AeroStage WM and compares
/// them with the installed versions. Only the two public release URLs are requested; nothing
/// about the Mac is sent besides what every HTTPS request carries.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Update: Identifiable {
        let component: UpdateComponent
        let installed: String
        let release: Release
        var id: UpdateComponent { component }
    }

    @Published private(set) var updates: [Update] = []
    @Published private(set) var isChecking = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastCheck: Date? {
        didSet { defaults.set(lastCheck, forKey: "lastUpdateCheck") }
    }

    /// Opens the update window; set by the app delegate.
    var showUpdates: () -> Void = {}

    private let settings: AppSettings
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private static let interval: TimeInterval = 24 * 60 * 60

    init(settings: AppSettings) {
        self.settings = settings
        lastCheck = defaults.object(forKey: "lastUpdateCheck") as? Date
    }

    /// Checks shortly after launch if the last check is a day old, then every hour looks again.
    func start() {
        Notifier.shared.onOpen = { [weak self] in self?.showUpdates() }
        Notifier.shared.attach()
        reportFailedInstall()
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        guard settings.checkForUpdates else { return }
        if let lastCheck, -lastCheck.timeIntervalSinceNow < Self.interval { return }
        Task { await check() }
    }

    /// `userInitiated`: from "Check Now" or the menu; shows the update window even without updates.
    func check(userInitiated: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        var found: [Update] = []
        do {
            for component in UpdateComponent.allCases {
                // The original AeroSpace is not updated by AeroStage.
                guard let installed = Self.installedVersion(of: component) else { continue }
                let latest = try await Self.latestRelease(of: component)
                if let release = UpdateComponent.update(installed: installed, latest: latest) {
                    found.append(Update(component: component, installed: installed, release: release))
                }
            }
            lastError = nil
        } catch {
            lastError = "Could not check for updates: \(error.localizedDescription)"
            NSLog("AeroStage: \(lastError!)")
            if userInitiated { showUpdates() }
            return
        }
        updates = found
        lastCheck = Date()
        NSLog("AeroStage: update check: \(found.isEmpty ? "up to date" : found.map { "\($0.component.title) \($0.installed) → \($0.release.version)" }.joined(separator: ", "))")
        if userInitiated {
            showUpdates()
        } else {
            notifyOnce(about: found)
        }
    }

    /// One notification per new version, so a skipped update does not come back every day.
    private func notifyOnce(about updates: [Update]) {
        let key = updates.map { "\($0.component.rawValue) \($0.release.version)" }.joined(separator: ", ")
        guard !updates.isEmpty, defaults.string(forKey: "notifiedUpdate") != key else { return }
        defaults.set(key, forKey: "notifiedUpdate")
        let names = updates.map { "\($0.component.title) \($0.release.version)" }.joined(separator: " and ")
        Notifier.shared.post(title: "Update available", body: "\(names) can be installed from the AeroStage menu.")
    }

    // MARK: Versions

    static func installedVersion(of component: UpdateComponent) -> String? {
        let url = component == .aeroStage
            ? Bundle.main.bundleURL
            : NSWorkspace.shared.urlForApplication(withBundleIdentifier: component.bundleID)
        return url.flatMap { Bundle(url: $0) }?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private static func latestRelease(of component: UpdateComponent) async throws -> Release {
        var request = URLRequest(url: component.latestReleaseURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AeroStage/\(installedVersion(of: .aeroStage) ?? "dev")", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "GitHub answered \(http.statusCode) for \(component.repository)"])
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    // MARK: Installing

    /// The update runs in a script after AeroStage quits; a failure is reported on the next launch.
    private func reportFailedInstall() {
        guard let status = try? String(contentsOf: UpdateInstaller.statusFile, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: UpdateInstaller.statusFile)
        guard status.trimmingCharacters(in: .whitespacesAndNewlines) != "0" else { return }
        lastError = "The last update failed. Details: \(UpdateInstaller.logFile.path)"
        Notifier.shared.post(title: "Update failed", body: "Homebrew could not install the update. See ~/Library/Logs/AeroStage/update.log.")
    }
}

/// Runs `brew upgrade` for the outdated casks. AeroStage WM is stopped first so that no windows
/// stay parked in the screen corner, AeroStage quits so its files can be replaced, and a detached
/// script reopens both afterwards.
enum UpdateInstaller {
    static let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AeroStage/update.log")
    static let statusFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AeroStage/update-status")

    static var brew: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// True if `component` was installed with its cask; otherwise the release page is offered.
    static func isInstalledWithHomebrew(_ component: UpdateComponent) -> Bool {
        guard let brew else { return false }
        let prefix = URL(fileURLWithPath: brew).deletingLastPathComponent().deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: prefix.appendingPathComponent("Caskroom/\(component.caskToken)").path)
    }

    static func canInstall(_ updates: [UpdateChecker.Update]) -> Bool {
        !updates.isEmpty && updates.allSatisfy { isInstalledWithHomebrew($0.component) }
    }

    /// `quitWindowManager` returns all windows to the screen and quits AeroStage WM, then calls back.
    @MainActor
    static func install(_ updates: [UpdateChecker.Update], quitWindowManager: (@escaping @MainActor () -> Void) -> Void) {
        guard let brew, canInstall(updates) else { return }
        let updatesWindowManager = updates.contains { $0.component == .windowManager }
        let reopenWindowManager = !NSRunningApplication.runningApplications(withBundleIdentifier: UpdateComponent.windowManager.bundleID).isEmpty
        let launch: @MainActor @Sendable () -> Void = {
            do {
                try runScript(brew: brew, casks: updates.map(\.component.cask), reopenWindowManager: reopenWindowManager)
                NSApp.terminate(nil)
            } catch {
                NSLog("AeroStage: update could not start: \(error)")
                NSSound.beep()
            }
        }
        if updatesWindowManager && reopenWindowManager {
            quitWindowManager(launch)
        } else {
            launch()
        }
    }

    private static func runScript(brew: String, casks: [String], reopenWindowManager: Bool) throws {
        try FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Waits for AeroStage to quit, so brew neither finds it running nor runs inside it.
        let script = """
            exec >> "$LOG" 2>&1
            echo "--- $(date): updating $*"
            while kill -0 "$PARENT" 2>/dev/null; do sleep 0.2; done
            "$BREW" update && "$BREW" upgrade --cask "$@"
            status=$?
            echo "$status" > "$STATUS"
            echo "exit $status"
            if [ "$REOPEN_WM" = 1 ]; then open -b \(UpdateComponent.windowManager.bundleID); sleep 2; fi
            open -b \(UpdateComponent.aeroStage.bundleID)
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "aerostage-update"] + casks
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(URL(fileURLWithPath: brew).deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["LOG"] = logFile.path
        environment["STATUS"] = statusFile.path
        environment["BREW"] = brew
        environment["PARENT"] = String(ProcessInfo.processInfo.processIdentifier)
        environment["REOPEN_WM"] = reopenWindowManager ? "1" : "0"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

/// macOS notifications; clicking one opens the update window.
final class Notifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = Notifier()
    @MainActor var onOpen: () -> Void = {}

    /// Notifications need an app bundle; a plain `swift run` has none.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    /// Set at launch, so clicking a notification from before a relaunch still opens the window.
    func attach() {
        center?.delegate = self
    }

    func post(title: String, body: String) {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: "update", content: content, trigger: nil))
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { onOpen() }
    }
}
