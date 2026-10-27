import AeroStageCore
import AppKit
import SwiftUI

/// Actions triggered from the sidebar, implemented in the AppDelegate.
@MainActor
struct SidebarActions {
    var focusWorkspace: (String) -> Void
    var focusWindow: (Int) -> Void
    var moveWindow: (Int, String) -> Void
    var moveWindowToCurrentStage: (Int) -> Void
    var moveWindowToNewStage: (Int) -> Void
    var toggleFloating: (Int) -> Void
    var newStage: () -> Void
    var closeWindow: (Int) -> Void
    var closeStage: (String) -> Void
    var setStageLayout: (String, String) -> Void
    var resetStageLayout: (String) -> Void
    var canAddStage: () -> Bool
    var openSettings: () -> Void
    var hideSidebar: () -> Void
    var quit: () -> Void
}

/// Text color and title size chosen in the settings, passed down to all sidebar views.
private struct SidebarInkKey: EnvironmentKey {
    static let defaultValue = Color.white
}

private struct SidebarTitleSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 14
}

private struct SidebarIconScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var sidebarInk: Color {
        get { self[SidebarInkKey.self] }
        set { self[SidebarInkKey.self] = newValue }
    }

    var sidebarTitleSize: CGFloat {
        get { self[SidebarTitleSizeKey.self] }
        set { self[SidebarTitleSizeKey.self] = newValue }
    }

    /// Scale for app icons in the grid and on thumbnails (1 = default size).
    var sidebarIconScale: CGFloat {
        get { self[SidebarIconScaleKey.self] }
        set { self[SidebarIconScaleKey.self] = newValue }
    }
}

struct SidebarView: View {
    @ObservedObject var store: StateStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var thumbnails: ThumbnailService
    let dragState: WindowDragState
    let actions: SidebarActions

    /// Thumbnails only with permission, icons otherwise.
    private var style: CardStyle {
        settings.cardStyle.usesThumbnails && thumbnails.access == .denied ? .icons : settings.cardStyle
    }

    private func metrics(for size: CGSize) -> CardMetrics {
        let canvas = thumbnails.canvas.size
        return CardMetrics(panelSize: size, style: style, titleSize: settings.titleSize, iconScale: settings.iconScale,
                           canvasAspect: canvas.width > 0 && canvas.height > 0 ? canvas.width / canvas.height : 16 / 9)
    }

    var body: some View {
        GeometryReader { geometry in
            // With many stages all previews shrink evenly, so every card stays visible.
            let previewHeight = style == .icons ? nil : metrics(for: geometry.size).contentHeight(forCount: store.stages.count)
            cards(previewHeight: previewHeight)
        }
        .background {
            ZStack {
                if settings.backgroundBlur { VisualEffectBackground() }
                Color(nsColor: settings.backgroundColor).opacity(settings.backgroundOpacity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .onPreferenceChange(DropFramesKey.self) { frames in
            MainActor.assumeIsolated { dragState.frames = frames }
        }
        .environmentObject(dragState)
        .environment(\.sidebarInk, Color(nsColor: settings.textColor))
        .environment(\.sidebarTitleSize, settings.titleSize)
        .environment(\.sidebarIconScale, settings.iconScale)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Settings …", action: actions.openSettings)
            Picker("View", selection: $settings.cardStyle) {
                ForEach(CardStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Mode", selection: $settings.displayMode) {
                ForEach(DisplayMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Button("Hide Sidebar", action: actions.hideSidebar)
            Divider()
            Button("Quit AeroStage", action: actions.quit)
        }
    }

    private func cards(previewHeight: CGFloat?) -> some View {
        VStack(spacing: CardMetrics.spacing) {
            ForEach(store.stages) { stage in
                StageCard(stage: stage, label: stage.label(for: settings.numbering), side: settings.side,
                          style: style, previewHeight: previewHeight, thumbnails: thumbnails, actions: actions)
            }
            if actions.canAddStage() {
                NewStageZone(actions: actions)
            }
            if !store.isConnected {
                Label("AeroSpace not reachable", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: settings.textColor).opacity(0.8))
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(CardMetrics.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StageCard: View {
    @Environment(\.sidebarInk) private var ink
    @Environment(\.sidebarTitleSize) private var titleSize
    let stage: Stage
    let label: String
    let side: SidebarSide
    let style: CardStyle
    /// Height of the preview area; `nil` = natural height (icon view).
    let previewHeight: CGFloat?
    // Observed so new images redraw the card even when the stage itself is unchanged.
    @ObservedObject var thumbnails: ThumbnailService
    let actions: SidebarActions
    @State private var hovering = false
    @State private var dropTargeted = false
    @EnvironmentObject private var dragState: WindowDragState

    /// A thumbnail or a real window is hovering over this card.
    private var highlighted: Bool { dropTargeted || dragState.hovered == .stage(stage.workspace) }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: CardMetrics.headerGap) {
            header
            Group {
                switch style {
                case .thumbnails:
                    WindowStack(windows: stage.windows, images: thumbnails.images, side: side, actions: actions)
                case .layout:
                    StageLayout(windows: stage.windows, images: thumbnails.images, frames: thumbnails.frames,
                                canvas: thumbnails.canvas.size, actions: actions)
                case .icons:
                    WindowIconGrid(windows: stage.windows, actions: actions)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: previewHeight)
        }
        .padding(CardMetrics.cardPadding)
        .background(shape.fill(fill))
        .overlay(shape.strokeBorder(stage.isFocused ? Color.accentColor : .clear, lineWidth: 2))
        .overlay(shape.strokeBorder(Color.accentColor.opacity(highlighted ? 0.8 : 0), style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
        .windowDropTarget(.stage(stage.workspace))
        .contentShape(shape)
        .onTapGesture { actions.focusWorkspace(stage.workspace) }
        .onHover { hovering = $0 }
        .dropDestination(for: String.self) { items, _ in
            let ids = items.compactMap(Int.init).filter { id in !stage.windows.contains { $0.windowId == id } }
            ids.forEach { actions.moveWindow($0, stage.workspace) }
            return !ids.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .contextMenu {
            Button("Switch to Stage") { actions.focusWorkspace(stage.workspace) }
            Menu("Layout") {
                Button("Side by Side") { actions.setStageLayout(stage.workspace, "tiles") }
                Button("Accordion") { actions.setStageLayout(stage.workspace, "accordion") }
                Divider()
                Button("Reset Layout") { actions.resetStageLayout(stage.workspace) }
            }
            .disabled(stage.windows.isEmpty)
            Divider()
            Button(stage.windows.count == 1 ? "Close Stage (1 Window)" : "Close Stage (\(stage.windows.count) Windows)") {
                actions.closeStage(stage.workspace)
            }
            .disabled(stage.windows.isEmpty)
        }
        .animation(.easeOut(duration: 0.12), value: stage.isFocused)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    /// "1. Firefox, Mail, Code": number and app names in order, without duplicates.
    private var header: some View {
        let names = stage.windows.map(\.appName).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return (Text("\(label). ").font(.system(size: titleSize + 3, weight: .bold, design: .rounded))
            + Text(names.isEmpty ? "Empty" : names.joined(separator: ", ")).font(.system(size: titleSize, weight: .semibold, design: .rounded)))
            .foregroundStyle(ink)
            .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(names.joined(separator: ", "))
    }

    private var fill: Color {
        if stage.isFocused { return Color.accentColor.opacity(0.3) }
        return ink.opacity(hovering ? 0.16 : 0.08)
    }
}

struct WindowIconGrid: View {
    @Environment(\.sidebarInk) private var ink
    @Environment(\.sidebarIconScale) private var iconScale
    private var iconSize: CGFloat { 44 * iconScale }
    let windows: [AeroWindow]
    let actions: SidebarActions
    private let maxVisible = 6

    var body: some View {
        if windows.isEmpty {
            Text("Empty")
                .font(.caption)
                .foregroundStyle(ink.opacity(0.6))
                .frame(maxWidth: .infinity, minHeight: 30)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: iconSize, maximum: iconSize * 1.25), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(windows.prefix(windows.count > maxVisible ? maxVisible - 1 : maxVisible)) { window in
                    WindowIcon(window: window, size: iconSize)
                        .windowInteractions(window, actions: actions)
                }
                if windows.count > maxVisible {
                    Text("+\(windows.count - maxVisible + 1)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(ink.opacity(0.8))
                        .frame(width: iconSize, height: iconSize)
                }
            }
        }
    }
}

/// Window thumbnails stacked like in Stage Manager; the most recently focused window is in front.
struct WindowStack: View {
    @Environment(\.sidebarInk) private var ink
    @Environment(\.sidebarIconScale) private var iconScale
    let windows: [AeroWindow]
    let images: [Int: CGImage]
    let side: SidebarSide
    let actions: SidebarActions
    private let maxLayers = 3

    var body: some View {
        if windows.isEmpty {
            Text("Empty")
                .font(.caption)
                .foregroundStyle(ink.opacity(0.6))
                .frame(maxWidth: .infinity, minHeight: 30)
        } else {
            let layers = Array(windows.prefix(maxLayers).enumerated())
            // The front window sits in the outer bottom corner; each layer behind it is shifted by
            // `step` towards the screen center and upwards, and slightly smaller.
            let corner: Alignment = side == .right ? .bottomTrailing : .bottomLeading
            let direction: CGFloat = side == .right ? -1 : 1
            GeometryReader { geometry in
                let size = geometry.size
                let step = CGSize(width: size.width * 0.12, height: size.height * 0.12)
                ZStack(alignment: corner) {
                    ForEach(layers.reversed(), id: \.element.id) { index, window in
                        let scale = 0.76 * pow(0.94, CGFloat(index))
                        WindowThumbnail(window: window, image: images[window.windowId], badgeSize: 36 * iconScale)
                            .frame(width: size.width * scale, height: size.height * scale)
                            .offset(x: direction * step.width * CGFloat(index), y: -step.height * CGFloat(index))
                            .brightness(index == 0 ? 0 : -0.06 * Double(index))
                            .windowInteractions(window, actions: actions)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: corner)
            }
            .aspectRatio(1.25, contentMode: .fit)
            .overlay(alignment: side == .right ? .bottomTrailing : .bottomLeading) {
                if windows.count > maxLayers {
                    Text("+\(windows.count - maxLayers)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                }
            }
        }
    }
}

/// The windows of a stage to scale at their actual position, like a miniature screen.
/// Windows without a known position (never visible yet) are laid out side by side.
struct StageLayout: View {
    @Environment(\.sidebarInk) private var ink
    @Environment(\.sidebarIconScale) private var iconScale
    let windows: [AeroWindow]
    let images: [Int: CGImage]
    let frames: [Int: CGRect]
    let canvas: CGSize
    let actions: SidebarActions

    private var aspect: CGFloat {
        canvas.width > 0 && canvas.height > 0 ? canvas.width / canvas.height : 16 / 9
    }

    var body: some View {
        if windows.isEmpty {
            Text("Empty")
                .font(.caption)
                .foregroundStyle(ink.opacity(0.6))
                .frame(maxWidth: .infinity, minHeight: 30)
        } else {
            let placed = placements()
            GeometryReader { geometry in
                let scale = geometry.size.width / max(canvas.width, 1)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(ink.opacity(0.08))
                    // Draw the most recently focused window (first in the list) last, i.e. on top.
                    ForEach(placed.reversed(), id: \.window.id) { item in
                        WindowThumbnail(window: item.window, image: images[item.window.windowId], badgeSize: 22 * iconScale)
                            .frame(width: item.frame.width * scale, height: item.frame.height * scale)
                            .offset(x: item.frame.minX * scale, y: item.frame.minY * scale)
                            .windowInteractions(item.window, actions: actions)
                    }
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
            // Windows partly off screen (e.g. moved by mouse) must not spill out of the card.
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }

    /// Real positions while they are consistent. AeroSpace only re-lays out a stage when it
    /// becomes visible, so after a window was moved to a hidden stage the remembered positions
    /// are stale (missing or overlapping). Then the windows are split evenly side by side,
    /// like AeroSpace's default tiling will arrange them.
    private func placements() -> [(window: AeroWindow, frame: CGRect)] {
        let known = windows.compactMap { window in frames[window.windowId].map { (window, $0) } }
        if known.count == windows.count, !overlaps(known.map(\.1)) {
            return known
        }
        // Keep the remembered left-to-right order, windows without a position at the end.
        let ordered = windows.sorted { a, b in
            switch (frames[a.windowId], frames[b.windowId]) {
            case let (x?, y?): x.minX < y.minX
            case (_?, nil): true
            default: false
            }
        }
        let width = canvas.width / CGFloat(ordered.count)
        return ordered.enumerated().map { index, window in
            (window, CGRect(x: CGFloat(index) * width, y: 0, width: width, height: canvas.height).insetBy(dx: 8, dy: 8))
        }
    }

    private func overlaps(_ rects: [CGRect]) -> Bool {
        for (i, a) in rects.enumerated() {
            for b in rects[(i + 1)...] {
                let overlap = a.intersection(b)
                guard !overlap.isNull else { continue }
                let smaller = min(a.width * a.height, b.width * b.height)
                if overlap.width * overlap.height > 0.1 * smaller { return true }
            }
        }
        return false
    }
}

/// A thumbnail with app icon; without an image just the icon on a neutral background.
struct WindowThumbnail: View {
    @Environment(\.sidebarInk) private var ink
    let window: AeroWindow
    let image: CGImage?
    var badgeSize: CGFloat = 36

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 6, style: .continuous) }

    var body: some View {
        let icon = IconCache.shared.icon(for: window)
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(ink.opacity(0.18), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    // App icon at the corner of the image, not of the (possibly wider) frame
                    .overlay(alignment: .bottomLeading) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: badgeSize, height: badgeSize)
                            .shadow(color: .black.opacity(0.3), radius: 1.5)
                            .offset(x: -badgeSize / 7, y: badgeSize / 7)
                    }
            } else {
                shape.fill(ink.opacity(0.1))
                    .overlay(Image(nsImage: icon).resizable().scaledToFit()
                        .frame(maxWidth: badgeSize * 1.4, maxHeight: badgeSize * 1.4).padding(4))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .help(window.windowTitle.isEmpty ? window.appName : "\(window.appName) – \(window.windowTitle)")
    }
}

struct WindowIcon: View {
    let window: AeroWindow
    var size: CGFloat = 44

    var body: some View {
        Image(nsImage: IconCache.shared.icon(for: window))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .help(window.windowTitle.isEmpty ? window.appName : "\(window.appName) – \(window.windowTitle)")
    }
}

/// App icons by bundle ID, loaded once.
@MainActor
final class IconCache {
    static let shared = IconCache()
    private var icons: [String: NSImage] = [:]

    func icon(for window: AeroWindow) -> NSImage {
        let key = window.appBundleId ?? window.appName
        if let cached = icons[key] { return cached }
        let icon = window.appBundleId
            .flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: window.appName)
            ?? NSImage()
        icons[key] = icon
        return icon
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Drop target and button at the end of the sidebar: drop a window here for a new stage,
/// click to open an empty one.
struct NewStageZone: View {
    @Environment(\.sidebarInk) private var ink
    @Environment(\.sidebarTitleSize) private var titleSize
    let actions: SidebarActions
    @State private var dropTargeted = false
    @EnvironmentObject private var dragState: WindowDragState

    private var targeted: Bool { dropTargeted || dragState.hovered == .newStage }
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        // Same color and shadow as the stage titles, so it stays readable on any background.
        Label("New Stage", systemImage: "plus.circle.fill")
            .font(.system(size: max(titleSize - 1, 11), weight: .semibold, design: .rounded))
            .foregroundStyle(targeted ? Color.accentColor : ink)
            .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
            .frame(maxWidth: .infinity, minHeight: CardMetrics.newStageHeight)
            .background(shape.fill(targeted ? Color.accentColor.opacity(0.22) : ink.opacity(hovering ? 0.16 : 0.08)))
            .overlay(shape.strokeBorder(targeted ? Color.accentColor : ink.opacity(hovering ? 0.95 : 0.7),
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4])))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .contentShape(shape)
            .onTapGesture { actions.newStage() }
            .onHover { hovering = $0 }
            .dropDestination(for: String.self) { items, _ in
                items.compactMap(Int.init).forEach(actions.moveWindowToNewStage)
                return true
            } isTargeted: { dropTargeted = $0 }
            .windowDropTarget(.newStage)
            .animation(.easeOut(duration: 0.12), value: targeted)
            .help("Drop a window here to put it on a new stage")
    }
}

extension View {
    /// Click to focus, drag to another stage, context menu: shared by thumbnails and icons.
    func windowInteractions(_ window: AeroWindow, actions: SidebarActions) -> some View {
        onTapGesture { actions.focusWindow(window.windowId) }
            .draggable(String(window.windowId)) {
                Image(nsImage: IconCache.shared.icon(for: window))
                    .resizable()
                    .frame(width: 40, height: 40)
            }
            .contextMenu {
                Button("Focus Window") { actions.focusWindow(window.windowId) }
                Button("Move to Current Stage") { actions.moveWindowToCurrentStage(window.windowId) }
                Button("Move to New Stage") { actions.moveWindowToNewStage(window.windowId) }
                Button("Toggle Floating / Tiling") { actions.toggleFloating(window.windowId) }
                Divider()
                Button("Close Window") { actions.closeWindow(window.windowId) }
            }
    }
}
