import AeroStageCore
import AppKit
import SwiftUI

/// App name and window title next to the sidebar while the mouse rests on a thumbnail or icon.
/// The sidebar never becomes active, and macOS shows no regular tooltips (`.help`) for such
/// panels, so AeroStage draws its own in a small click-through panel beside the sidebar.
@MainActor
final class WindowTooltip {
    private let panel: NSPanel
    private let sidebar: NSWindow
    private let settings: AppSettings
    private var showTask: Task<Void, Never>?
    private var monitor: Any?
    private static let delay: Duration = .milliseconds(500)

    init(sidebar: NSWindow, settings: AppSettings) {
        self.sidebar = sidebar
        self.settings = settings
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = sidebar.level
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // A click or drag starts something else; the tooltip would only be in the way.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.hide() }
            return event
        }
    }

    /// `rect` is the hovered view in the sidebar's content coordinates (top-left origin);
    /// `nil` when the mouse left it.
    func hover(_ window: AeroWindow?, rect: CGRect) {
        showTask?.cancel()
        guard let window else { return hide() }
        if panel.isVisible {
            // Moving from one window to the next: switch right away, like system tooltips.
            show(window, rect: rect)
            return
        }
        showTask = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            self?.show(window, rect: rect)
        }
    }

    func hide() {
        showTask?.cancel()
        showTask = nil
        panel.orderOut(nil)
    }

    private func show(_ window: AeroWindow, rect: CGRect) {
        guard sidebar.isVisible, sidebar.alphaValue > 0.5, NSEvent.pressedMouseButtons == 0 else { return }
        let hosting = NSHostingView(rootView: WindowTooltipView(app: window.appName, title: window.windowTitle))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        // Beside the sidebar, towards the screen center, level with the hovered window.
        let sidebarFrame = sidebar.frame
        let anchorY = sidebarFrame.maxY - rect.midY
        var origin = NSPoint(
            x: settings.side == .right ? sidebarFrame.minX - size.width - 6 : sidebarFrame.maxX + 6,
            y: anchorY - size.height / 2)
        if let visible = (sidebar.screen ?? NSScreen.main)?.visibleFrame {
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }
}

struct WindowTooltipView: View {
    let app: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(app)
                .font(.system(size: 12, weight: .semibold))
            if !title.isEmpty, title != app {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 300, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
    }
}
