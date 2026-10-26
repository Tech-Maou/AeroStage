import AeroStageCore
import AppKit
import SwiftUI

/// Actions triggered from the sidebar, implemented in the AppDelegate.
@MainActor
struct SidebarActions {
    var focusWorkspace: (String) -> Void
    var focusWindow: (Int) -> Void
    var openSettings: () -> Void
    var hideSidebar: () -> Void
    var quit: () -> Void
}

struct SidebarView: View {
    @ObservedObject var store: StateStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var thumbnails: ThumbnailService
    let actions: SidebarActions

    /// Thumbnails only with permission, icons otherwise.
    private var style: CardStyle {
        settings.cardStyle.usesThumbnails && thumbnails.access == .denied ? .icons : settings.cardStyle
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(store.stages) { stage in
                StageCard(stage: stage, label: stage.label(for: settings.numbering), side: settings.side,
                          style: style, thumbnails: thumbnails, actions: actions)
            }
            if !store.isConnected {
                Label("AeroSpace not reachable", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground().clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
        .contentShape(Rectangle())
        .contextMenu {
            Button("Settings …", action: actions.openSettings)
            Picker("View", selection: $settings.cardStyle) {
                ForEach(CardStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Button("Hide Sidebar", action: actions.hideSidebar)
            Divider()
            Button("Quit AeroStage", action: actions.quit)
        }
    }
}

struct StageCard: View {
    let stage: Stage
    let label: String
    let side: SidebarSide
    let style: CardStyle
    // Observed so new images redraw the card even when the stage itself is unchanged.
    @ObservedObject var thumbnails: ThumbnailService
    let actions: SidebarActions
    @State private var hovering = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
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
        }
        .padding(6)
        .background(shape.fill(fill))
        .overlay(shape.strokeBorder(stage.isFocused ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(shape)
        .onTapGesture { actions.focusWorkspace(stage.workspace) }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: stage.isFocused)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    /// "1. Firefox, Mail, Code": number and app names in order, without duplicates.
    private var header: some View {
        let names = stage.windows.map(\.appName).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return (Text("\(label). ").fontWeight(.bold).foregroundColor(stage.isFocused ? .accentColor : .primary)
            + Text(names.isEmpty ? "Empty" : names.joined(separator: ", ")).foregroundColor(.secondary))
            .font(.system(size: 11, design: .rounded))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(names.joined(separator: ", "))
    }

    private var fill: Color {
        if stage.isFocused { return Color.accentColor.opacity(0.18) }
        return Color.primary.opacity(hovering ? 0.12 : 0.06)
    }
}

struct WindowIconGrid: View {
    let windows: [AeroWindow]
    let actions: SidebarActions
    private let maxVisible = 6

    var body: some View {
        if windows.isEmpty {
            Text("Empty")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 30)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 40), spacing: 4)], alignment: .leading, spacing: 4) {
                ForEach(windows.prefix(windows.count > maxVisible ? maxVisible - 1 : maxVisible)) { window in
                    WindowIcon(window: window)
                        .onTapGesture { actions.focusWindow(window.windowId) }
                }
                if windows.count > maxVisible {
                    Text("+\(windows.count - maxVisible + 1)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
            }
        }
    }
}

/// Window thumbnails stacked like in Stage Manager; the most recently focused window is in front.
struct WindowStack: View {
    let windows: [AeroWindow]
    let images: [Int: CGImage]
    let side: SidebarSide
    let actions: SidebarActions
    private let maxLayers = 3

    var body: some View {
        if windows.isEmpty {
            Text("Empty")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
                        WindowThumbnail(window: window, image: images[window.windowId])
                            .frame(width: size.width * scale, height: size.height * scale)
                            .offset(x: direction * step.width * CGFloat(index), y: -step.height * CGFloat(index))
                            .brightness(index == 0 ? 0 : -0.06 * Double(index))
                            .onTapGesture { actions.focusWindow(window.windowId) }
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
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 30)
        } else {
            let placed = placements()
            GeometryReader { geometry in
                let scale = geometry.size.width / max(canvas.width, 1)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                    // Draw the most recently focused window (first in the list) last, i.e. on top.
                    ForEach(placed.reversed(), id: \.window.id) { item in
                        WindowThumbnail(window: item.window, image: images[item.window.windowId], badgeSize: 12)
                            .frame(width: item.frame.width * scale, height: item.frame.height * scale)
                            .offset(x: item.frame.minX * scale, y: item.frame.minY * scale)
                            .onTapGesture { actions.focusWindow(item.window.windowId) }
                    }
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
        }
    }

    private func placements() -> [(window: AeroWindow, frame: CGRect)] {
        let unknown = windows.filter { frames[$0.windowId] == nil }
        let width = canvas.width / CGFloat(max(unknown.count, 1))
        return windows.map { window in
            if let frame = frames[window.windowId] { return (window, frame) }
            let index = CGFloat(unknown.firstIndex(of: window) ?? 0)
            return (window, CGRect(x: index * width, y: 0, width: width, height: canvas.height).insetBy(dx: 8, dy: 8))
        }
    }
}

/// A thumbnail with app icon; without an image just the icon on a neutral background.
struct WindowThumbnail: View {
    let window: AeroWindow
    let image: CGImage?
    var badgeSize: CGFloat = 22

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
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
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
                shape.fill(Color.primary.opacity(0.08))
                    .overlay(Image(nsImage: icon).resizable().frame(width: badgeSize * 1.4, height: badgeSize * 1.4))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .help(window.windowTitle.isEmpty ? window.appName : "\(window.appName) – \(window.windowTitle)")
    }
}

struct WindowIcon: View {
    let window: AeroWindow

    var body: some View {
        Image(nsImage: IconCache.shared.icon(for: window))
            .resizable()
            .interpolation(.high)
            .frame(width: 30, height: 30)
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
