// Draws the 1024 px app icons for AeroStage and AeroStage WM.
// Usage: swift scripts/make-icons.swift <aerostage.png> <aerostage-wm.png>
import AppKit

let size: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let teal = color(0x3DD6C8), blue = color(0x4C8DFF), violet = color(0x9B6CFF)

/// Renders into a bitmap with a top-left origin, so rects read like a layout.
func render(_ path: String, draw: (CGContext) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1)
    drawBackground(context)
    draw(context)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

/// macOS icon grid: 824 px rounded square with a dark gradient.
func drawBackground(_ c: CGContext) {
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.35))
    c.addPath(shape)
    c.setFillColor(color(0x121826))
    c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(shape)
    c.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [color(0x2E3D5C), color(0x111722)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    c.restoreGState()
}

func roundedRect(_ c: CGContext, _ rect: CGRect, radius: CGFloat, fill: CGColor, shadow: Bool = true) {
    c.saveGState()
    if shadow { c.setShadow(offset: CGSize(width: 0, height: 10), blur: 22, color: color(0x000000, 0.45)) }
    c.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    c.setFillColor(fill)
    c.fillPath()
    c.restoreGState()
}

/// A window with a title bar and the three traffic-light dots.
func window(_ c: CGContext, _ rect: CGRect, accent: CGColor) {
    roundedRect(c, rect, radius: 34, fill: color(0xE9EEF6))
    c.saveGState()
    c.addPath(CGPath(roundedRect: rect, cornerWidth: 34, cornerHeight: 34, transform: nil))
    c.clip()
    c.setFillColor(accent)
    c.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 64))
    c.restoreGState()
    for (i, dot) in [color(0xFF5F57), color(0xFEBC2E), color(0x28C840)].enumerated() {
        c.setFillColor(dot)
        c.fillEllipse(in: CGRect(x: rect.minX + 28 + CGFloat(i) * 36, y: rect.minY + 20, width: 24, height: 24))
    }
    // Content lines
    c.setFillColor(color(0x9AA6B8, 0.55))
    for row in 0..<3 {
        let y = rect.minY + 110 + CGFloat(row) * 52
        guard y + 22 < rect.maxY - 30 else { break }
        c.fill(CGRect(x: rect.minX + 36, y: y, width: (rect.width - 72) * (row == 2 ? 0.6 : 1), height: 22))
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: swift scripts/make-icons.swift <aerostage.png> <aerostage-wm.png>")
    exit(2)
}

// AeroStage: a large window and the stage strip on the right.
render(arguments[1]) { c in
    window(c, CGRect(x: 180, y: 250, width: 470, height: 520), accent: blue)
    let cards: [(CGFloat, CGColor)] = [(220, teal), (420, blue), (620, violet)]
    for (y, accent) in cards {
        // Two stacked thumbnails per card, like Stage Manager.
        roundedRect(c, CGRect(x: 706, y: y - 18, width: 138, height: 150), radius: 22, fill: color(0x5B6B88))
        window(c, CGRect(x: 690, y: y, width: 150, height: 160), accent: accent)
    }
}

// AeroStage WM: tiled windows.
render(arguments[2]) { c in
    window(c, CGRect(x: 180, y: 190, width: 320, height: 644), accent: blue)
    window(c, CGRect(x: 524, y: 190, width: 320, height: 310), accent: teal)
    window(c, CGRect(x: 524, y: 524, width: 320, height: 310), accent: violet)
}
print("Wrote \(arguments[1]) and \(arguments[2])")
