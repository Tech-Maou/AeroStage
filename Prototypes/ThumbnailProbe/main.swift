// Phase 0 prototype: can ScreenCaptureKit capture windows that AeroSpace has hidden?
// Usage: ThumbnailProbe <windowId> <out.png>
import AppKit
import Foundation
import ScreenCaptureKit

@main
struct ThumbnailProbe {
    static func main() async {
        // Sets up the WindowServer connection; without it SCK crashes when capturing
        _ = NSApplication.shared
        let args = CommandLine.arguments
        guard args.count >= 3, let windowID = UInt32(args[1]) else {
            print("usage: ThumbnailProbe <windowId> <out.png>")
            exit(2)
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                print("window \(windowID) not found")
                exit(1)
            }
            print("frame=\(window.frame) onScreen=\(window.isOnScreen)")
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * 2)
            config.height = Int(window.frame.height * 2)
            config.showsCursor = false
            let start = Date()
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: config)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try png.write(to: URL(fileURLWithPath: args[2]))
            print("ok \(image.width)x\(image.height) in \(ms) ms")
        } catch {
            print("error: \(error)")
            exit(1)
        }
    }
}
