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
///
/// Reserved mode: always shown, AeroSpace keeps its space free.
/// Overlay mode: hidden until the mouse touches the screen edge (or `aerostage toggle`),
/// then it floats above the windows and hides again when the mouse leaves it.
@MainActor
final class SidebarController {
    private let panel = SidebarPanel()
    private let settings: AppSettings
    private var screen: NSScreen?
    private var mouseMonitors: [Any] = []
    private var revealTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    /// Shown via shortcut: stays until toggled, a stage is chosen, or the mouse visited and left.
    private var pinned = false
    private var mouseWasInside = false
    /// Shown because a window is being dragged towards the sidebar.
    private var revealedByWindowDrag = false
    /// A context menu of the sidebar is open; the menu extends beyond the panel, so leaving
    /// the panel must not hide it.
    private var openMenus = 0 {
        didSet { if (oldValue > 0) != (openMenus > 0) { onMenuTrackingChange?(openMenus > 0) } }
    }
    private var menuOpen: Bool { openMenus > 0 }
    var onMenuTrackingChange: ((Bool) -> Void)?
    private var menuObservers: [NSObjectProtocol] = []

    private(set) var isShown = false
    private lazy var tooltip = WindowTooltip(sidebar: panel, settings: settings)
    var onVisibilityChange: ((Bool) -> Void)?

    init(store: StateStore, settings: AppSettings, thumbnails: ThumbnailService, dragState: WindowDragState,
         watch: WindowManagerWatch, actions: SidebarActions) {
        self.settings = settings
        panel.acceptsMouseMovedEvents = true
        observeMenus()
        panel.contentView = FirstMouseHostingView(
            rootView: SidebarView(store: store, settings: settings, thumbnails: thumbnails, dragState: dragState,
                                  watch: watch, actions: actions))
    }

    var isOverlay: Bool { settings.displayMode == .overlay }

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
        self.screen = screen
        guard let screen, settings.sidebarVisible else {
            stopMouseTracking()
            setShown(false, animated: false)
            return
        }
        panel.setFrame(frame(on: screen), display: true)
        if isOverlay {
            startMouseTracking()
            if isShown { panel.orderFrontRegardless() } else { park() }
        } else {
            stopMouseTracking()
            setShown(true, animated: false)
        }
    }

    /// `aerostage toggle`: overlay shows/hides temporarily, reserved mode switches the sidebar off/on.
    func toggle() {
        if isOverlay, settings.sidebarVisible {
            pinned = !isShown
            mouseWasInside = false
            setShown(!isShown, animated: true)
        } else {
            settings.sidebarVisible.toggle()
        }
    }

    /// Frame of the panel while it is on screen, for hit testing dragged windows.
    var visibleFrame: NSRect? {
        panel.isVisible && isShown ? panel.frame : nil
    }

    /// A window is dragged: the overlay appears as soon as the cursor reaches the edge.
    func windowDragMoved(to point: NSPoint) {
        guard isOverlay, !isShown, isAtEdge(point) else { return }
        revealedByWindowDrag = true
        pinned = true
        setShown(true, animated: true)
    }

    func windowDragEnded() {
        guard revealedByWindowDrag else { return }
        revealedByWindowDrag = false
        dismissOverlay()
    }

    private func isAtEdge(_ point: NSPoint) -> Bool {
        guard let screen else { return false }
        let bounds = screen.frame
        guard point.y >= bounds.minY, point.y <= bounds.maxY else { return false }
        // During a window drag the cursor rarely hits the last pixel, so allow a few points.
        return settings.side == .right ? point.x >= bounds.maxX - 6 : point.x <= bounds.minX + 5
    }

    /// After choosing a stage or window: the overlay gets out of the way.
    func dismissOverlay() {
        guard isOverlay, isShown else { return }
        pinned = false
        setShown(false, animated: true)
    }

    func panelSize(on screen: NSScreen) -> CGSize {
        frame(on: screen).size
    }

    private func frame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let gap = CGFloat(settings.outerGap)
        let width = width(on: screen)
        let x = settings.side == .right ? visible.maxX - gap - width : visible.minX + gap
        return NSRect(x: x, y: visible.minY + gap, width: width, height: visible.height - 2 * gap)
    }

    private func cancelReveal() {
        revealTask?.cancel()
        revealTask = nil
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
    }

    /// Tooltip for the window under the mouse (`nil`: the mouse left it).
    func hoverWindow(_ window: AeroWindow?, rect: CGRect) {
        tooltip.hover(isShown ? window : nil, rect: rect)
    }

    private func setShown(_ shown: Bool, animated: Bool) {
        if !shown { tooltip.hide() }
        cancelReveal()
        cancelHide()
        guard shown != isShown || (shown && !panel.isVisible) else { return }
        isShown = shown
        if !shown { pinned = false; mouseWasInside = false }

        guard let screen else {
            removeFromScreen()
            onVisibilityChange?(isShown)
            return
        }
        let target = frame(on: screen)
        // Slide in from / out to the screen edge.
        let offset: CGFloat = settings.side == .right ? 24 : -24
        let away = target.offsetBy(dx: offset, dy: 0)

        if shown {
            panel.ignoresMouseEvents = false
            if animated {
                panel.alphaValue = 0
                panel.setFrame(away, display: false)
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().alphaValue = 1
                    panel.animator().setFrame(target, display: true)
                }
            } else {
                panel.alphaValue = 1
                panel.setFrame(target, display: true)
                panel.orderFrontRegardless()
            }
        } else if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
                panel.animator().setFrame(away, display: true)
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.isShown else { return }
                    self.hideCompletely()
                }
            })
        } else {
            hideCompletely()
        }
        onVisibilityChange?(isShown)
    }

    /// A hidden overlay stays on screen, transparent and click-through. That keeps SwiftUI
    /// laying out the cards, so the drop targets for dragged windows are always current.
    private func park() {
        guard let screen else { return removeFromScreen() }
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        panel.setFrame(frame(on: screen), display: true)
        panel.orderFrontRegardless()
    }

    private func removeFromScreen() {
        panel.orderOut(nil)
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
    }

    private func hideCompletely() {
        if isOverlay, settings.sidebarVisible { park() } else { removeFromScreen() }
    }

    // MARK: Overlay edge trigger

    private func startMouseTracking() {
        guard mouseMonitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        // Global: mouse over other apps; local: mouse over the sidebar itself.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved(to: NSEvent.mouseLocation) }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved(to: NSEvent.mouseLocation) }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func stopMouseTracking() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
        cancelReveal()
        cancelHide()
    }

    private func mouseMoved(to point: NSPoint) {
        guard isOverlay, let screen else { return }
        let bounds = screen.frame
        let onScreen = point.y >= bounds.minY && point.y <= bounds.maxY
        let atEdge = settings.edgeTrigger && onScreen
            && (settings.side == .right ? point.x >= bounds.maxX - 2 : point.x <= bounds.minX + 1)

        if !isShown {
            if atEdge { scheduleReveal() } else { cancelReveal() }
            return
        }

        let near = panel.frame.insetBy(dx: -20, dy: -20).contains(point) || atEdge
        if near || menuOpen {
            mouseWasInside = true
            cancelHide()
        } else if (mouseWasInside || !pinned) && NSEvent.pressedMouseButtons == 0 {
            scheduleHide()
        }
    }

    private func observeMenus() {
        let center = NotificationCenter.default
        menuObservers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Submenus (e.g. "View") send their own begin/end, hence a counter.
                    guard let self, self.isShown || self.menuOpen else { return }
                    self.openMenus += 1
                    self.cancelHide()
                }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.menuOpen else { return }
                    self.openMenus -= 1
                    guard !self.menuOpen else { return }
                    // Re-check where the mouse is now: outside, the overlay hides as usual.
                    self.mouseMoved(to: NSEvent.mouseLocation)
                }
            },
        ]
    }

    private func scheduleReveal() {
        guard revealTask == nil else { return }
        let delay = settings.revealDelay
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.revealTask = nil
            self.mouseWasInside = true
            self.setShown(true, animated: true)
        }
    }

    private func scheduleHide() {
        guard hideTask == nil else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            self.hideTask = nil
            self.setShown(false, animated: true)
        }
    }
}
