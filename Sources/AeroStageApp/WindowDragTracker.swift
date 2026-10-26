import AppKit
import SwiftUI

/// Drop targets in the sidebar and the one under a window that is being dragged.
@MainActor
final class WindowDragState: ObservableObject {
    enum Target: Hashable {
        case stage(String)
        case newStage
    }

    @Published var hovered: Target?
    /// Frames of the drop targets in the panel's content view (top-left origin).
    var frames: [Target: CGRect] = [:]
}

struct DropFramesKey: PreferenceKey {
    static var defaultValue: [WindowDragState.Target: CGRect] { [:] }

    static func reduce(value: inout [WindowDragState.Target: CGRect], nextValue: () -> [WindowDragState.Target: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Reports this view's frame as a drop target for dragged windows.
    func windowDropTarget(_ target: WindowDragState.Target) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: DropFramesKey.self, value: [target: geometry.frame(in: .global)])
        })
    }
}

/// Lets you grab a real window by its title bar and drop it onto the sidebar.
///
/// A global mouse-down starts watching; while the button is held, the tracker polls the
/// cursor (window drags are not always delivered as drag events to other apps) and checks
/// whether the window under the initial click actually moves. Once it does, the sidebar
/// is revealed and the target under the cursor highlighted. Releasing over a target moves
/// the window there.
@MainActor
final class WindowDragTracker {
    private let state: WindowDragState
    private let panelFrame: () -> NSRect?
    private let isManaged: (Int) -> Bool
    var onDragMove: (NSPoint) -> Void = { _ in }
    var onDragEnd: () -> Void = {}
    var onDrop: (Int, WindowDragState.Target) -> Void = { _, _ in }

    private var monitor: Any?
    private var timer: Timer?
    private var windowID: Int?
    private var startBounds: CGRect?
    private var confirmed = false

    init(state: WindowDragState, panelFrame: @escaping () -> NSRect?, isManaged: @escaping (Int) -> Bool) {
        self.state = state
        self.panelFrame = panelFrame
        self.isManaged = isManaged
    }

    func start() {
        guard monitor == nil else { return }
        // Global only: drags that start inside the sidebar are SwiftUI drag & drop.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown(at: NSEvent.mouseLocation) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        finish(drop: false)
    }

    private func mouseDown(at point: NSPoint) {
        finish(drop: false)
        guard let (id, bounds) = Self.window(at: point), isManaged(id) else { return }
        windowID = id
        startBounds = bounds
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let windowID else { return finish(drop: false) }
        if NSEvent.pressedMouseButtons & 1 == 0 {
            return finish(drop: confirmed)
        }
        if !confirmed {
            // Only a window that actually moves counts, not a click or a text selection.
            guard let start = startBounds, let now = Self.bounds(of: windowID),
                  abs(now.minX - start.minX) + abs(now.minY - start.minY) > 6
            else { return }
            confirmed = true
        }
        let point = NSEvent.mouseLocation
        onDragMove(point)
        let target = target(at: point)
        if state.hovered != target { state.hovered = target }
    }

    private func finish(drop: Bool) {
        timer?.invalidate()
        timer = nil
        let target = state.hovered
        if let id = windowID, drop, let target { onDrop(id, target) }
        if confirmed { onDragEnd() }
        if state.hovered != nil { state.hovered = nil }
        windowID = nil
        startBounds = nil
        confirmed = false
    }

    private func target(at point: NSPoint) -> WindowDragState.Target? {
        // Also accept the margin between the panel and the screen edge, where the cursor
        // naturally ends up when a window is pushed against the side.
        guard let panel = panelFrame(), panel.insetBy(dx: -16, dy: 0).contains(point) else { return nil }
        // SwiftUI frames are top-left based inside the panel.
        // Cards span the sidebar's width, so only the height decides.
        let y = panel.maxY - point.y
        return state.frames.first { $0.value.minY - 3 <= y && y <= $0.value.maxY + 3 }?.key
    }

    // MARK: Window server queries

    /// Converts a Cocoa screen point (bottom-left origin) to CG coordinates (top-left origin).
    private static func cgPoint(_ point: NSPoint) -> CGPoint {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: point.x, y: height - point.y)
    }

    /// Frontmost normal window under the point, ignoring AeroStage's own windows.
    private static func window(at point: NSPoint) -> (Int, CGRect)? {
        let location = cgPoint(point)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != ProcessInfo.processInfo.processIdentifier,
                  let id = info[kCGWindowNumber as String] as? Int,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.contains(location)
            else { continue }
            return (id, bounds)
        }
        return nil
    }

    private static func bounds(of windowID: Int) -> CGRect? {
        let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowID)) as? [[String: Any]]
        guard let dict = list?.first?[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dict)
    }
}
