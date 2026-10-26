import AeroStageCore
import AppKit
import SwiftUI

/// Borderless panel that never takes focus and is visible on all Spaces.
final class SidebarPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Accepts clicks without the panel having to be activated first.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Positions the sidebar on the sidebar monitor and shows or hides it.
@MainActor
final class SidebarController {
    private let panel = SidebarPanel()
    private let settings: AppSettings

    init(store: StateStore, settings: AppSettings, thumbnails: ThumbnailService, actions: SidebarActions) {
        self.settings = settings
        panel.contentView = FirstMouseHostingView(
            rootView: SidebarView(store: store, settings: settings, thumbnails: thumbnails, actions: actions))
    }

    /// Sidebar width on this monitor, in points.
    func width(on screen: NSScreen) -> CGFloat {
        let raw = screen.frame.width * settings.widthPercent / 100
        return min(max(raw, settings.minWidth), max(settings.minWidth, settings.maxWidth)).rounded()
    }

    /// Gap AeroSpace has to leave free at the sidebar edge: margin + sidebar + margin.
    func reservedGap(on screen: NSScreen) -> Int {
        Int(width(on: screen)) + 2 * settings.outerGap
    }

    func layout(on screen: NSScreen?) {
        guard let screen, settings.sidebarVisible else {
            panel.orderOut(nil)
            return
        }
        let visible = screen.visibleFrame
        let gap = CGFloat(settings.outerGap)
        let width = width(on: screen)
        let x = settings.side == .right ? visible.maxX - gap - width : visible.minX + gap
        let frame = NSRect(x: x, y: visible.minY + gap, width: width, height: visible.height - 2 * gap)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }
}
