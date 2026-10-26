import AppKit
import ScreenCaptureKit

/// Captures the sidebar's windows via ScreenCaptureKit and caches the images.
///
/// AeroSpace only parks windows of inactive workspaces in a screen corner; macOS keeps
/// rendering them, so their thumbnails stay current as well (see SPEC.md, phase 0).
@MainActor
final class ThumbnailService: ObservableObject {
    enum Access: Equatable {
        case unknown, granted, denied
    }

    @Published private(set) var images: [Int: CGImage] = [:]
    /// Last real position per window, relative to `canvas`. Hidden windows (parked in the
    /// corner) keep the position they last had while visible.
    @Published private(set) var frames: [Int: CGRect] = [:]
    @Published private(set) var access: Access = .unknown

    /// Target width of a thumbnail in pixels.
    var targetWidth: CGFloat = 480
    /// Live refresh interval; `nil` = only on changes.
    var interval: Duration? = .seconds(3)
    /// Window area of the sidebar monitor in global CG coordinates (without the sidebar).
    var canvas: CGRect = .zero

    private(set) var lastCapture: Date?
    /// While true, new images are held back. Publishing redraws the sidebar, and SwiftUI then
    /// rebuilds an open context menu, which closes its submenus.
    var isPaused = false {
        didSet { if !isPaused { publishPending() } }
    }
    private var pendingImages: [Int: CGImage] = [:]
    private var pendingFrames: [Int: CGRect] = [:]
    private var windowIDs: [Int] = []
    private var loop: Task<Void, Never>?
    private var requestedAccess = false

    var isRunning: Bool { loop != nil }

    /// Sets the windows to capture (front = first) and captures right away.
    func update(windowIDs: [Int]) {
        let changed = windowIDs != self.windowIDs
        self.windowIDs = windowIDs
        let keep = Set(windowIDs)
        if images.keys.contains(where: { !keep.contains($0) }) {
            images = images.filter { keep.contains($0.key) }
        }
        if frames.keys.contains(where: { !keep.contains($0) }) {
            frames = frames.filter { keep.contains($0.key) }
        }
        if changed || loop == nil { restart() }
    }

    /// Captures right away and continues with the current interval.
    func refreshNow() {
        restart()
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Requests screen recording permission (system dialog only the first time).
    func requestAccess() {
        requestedAccess = true
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        restart()
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func restart() {
        loop?.cancel()
        loop = Task { [weak self] in
            // Capture now and once more after AeroSpace has re-laid out the windows.
            await self?.captureAll()
            try? await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled {
                guard let self else { return }
                await self.captureAll()
                // Without permission retry less often; it can be granted at any time.
                let pause = self.access == .denied ? .seconds(10) : self.interval
                guard let pause else { break }
                try? await Task.sleep(for: pause)
            }
        }
    }

    private func captureAll() async {
        guard !windowIDs.isEmpty else { return }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            if access != .denied { access = .denied }
            if !requestedAccess {
                requestedAccess = true
                CGRequestScreenCaptureAccess()
            }
            return
        }
        if access != .granted { access = .granted }

        let byID = Dictionary(content.windows.map { (Int($0.windowID), $0) }, uniquingKeysWith: { first, _ in first })
        var captured: [Int: CGImage] = [:]
        var positions: [Int: CGRect] = [:]
        for id in windowIDs {
            guard !Task.isCancelled, let window = byID[id], window.frame.width > 1, window.frame.height > 1 else { continue }
            if let frame = visibleFrame(of: window) {
                positions[id] = frame
            }
            if let image = try? await capture(window) {
                captured[id] = image
            }
        }
        guard !Task.isCancelled else { return }
        lastCapture = Date()
        pendingImages.merge(captured) { _, new in new }
        pendingFrames.merge(positions) { _, new in new }
        if !isPaused { publishPending() }
    }

    private func publishPending() {
        let keep = Set(windowIDs)
        if !pendingImages.isEmpty {
            images.merge(pendingImages.filter { keep.contains($0.key) }) { _, new in new }
        }
        let changed = pendingFrames.filter { keep.contains($0.key) && frames[$0.key] != $0.value }
        if !changed.isEmpty { frames.merge(changed) { _, new in new } }
        pendingImages.removeAll()
        pendingFrames.removeAll()
    }

    /// Position relative to `canvas`, but only if the window lies mostly inside it.
    /// AeroSpace parks hidden windows off screen except for a single pixel.
    private func visibleFrame(of window: SCWindow) -> CGRect? {
        guard !canvas.isEmpty else { return nil }
        let frame = window.frame
        let overlap = frame.intersection(canvas)
        guard !overlap.isNull, overlap.width * overlap.height > 0.5 * frame.width * frame.height else { return nil }
        return frame.offsetBy(dx: -canvas.minX, dy: -canvas.minY)
    }

    private func capture(_ window: SCWindow) async throws -> CGImage {
        let config = SCStreamConfiguration()
        let scale = min(1, targetWidth / window.frame.width)
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window),
            configuration: config)
    }
}
