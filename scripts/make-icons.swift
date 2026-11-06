// Renders the extension, toolbar and app icons from SF Symbols.
// Usage: swift scripts/make-icons.swift <project-dir>
import AppKit

let project = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let extDir = project.appendingPathComponent("WebExtension/images", isDirectory: true)
let appIconDir = project.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
for dir in [extDir, appIconDir] {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
}

// SharePoint-style teal palette (inspired by, not copying, Microsoft's logo).
func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let tealDark = rgb(0x036C70), teal = rgb(0x1A9BA1), tealLight = rgb(0x37C6D0)

/// Three overlapping circles in teal shades, filling `rect` (back to front: dark, mid, light).
func drawCircles(in rect: NSRect) {
    let d = rect.width * 0.62
    let circles: [(NSColor, CGFloat, CGFloat)] = [
        (tealDark, rect.minX + rect.width * 0.08, rect.maxY - d),
        (teal, rect.maxX - d, rect.minY + rect.height * 0.30),
        (tealLight, rect.minX + rect.width * 0.20, rect.minY),
    ]
    for (color, x, y) in circles {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: d, height: d)).fill()
    }
}

/// White disc with a teal download arrow, the "download" badge used on both icons.
func drawDownloadBadge(in rect: NSRect) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = rect.width * 0.08
    shadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.03)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: rect).fill()
    NSGraphicsContext.restoreGraphicsState()
    drawSymbol("arrow.down", in: rect.insetBy(dx: rect.width * 0.24, dy: rect.height * 0.22),
               colors: [tealDark], weight: .bold)
}

func png(size: Int, draw: (CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// Draws an SF Symbol centred in `rect`, scaled to fit.
func drawSymbol(_ name: String, in rect: NSRect, colors: [NSColor], weight: NSFont.Weight = .regular) {
    let config = NSImage.SymbolConfiguration(pointSize: rect.height, weight: weight)
        .applying(.init(paletteColors: colors))
    let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let s = symbol.size
    let scale = min(rect.width / s.width, rect.height / s.height)
    let w = s.width * scale, h = s.height * scale
    symbol.draw(in: NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
}

// Extension icon (Safari settings): teal circles with a download badge.
for size in [48, 96, 128, 256, 512] {
    let data = png(size: size) { px in
        let area = NSRect(x: 0, y: 0, width: px, height: px).insetBy(dx: px * 0.04, dy: px * 0.04)
        drawCircles(in: area)
        let b = px * 0.46
        drawDownloadBadge(in: NSRect(x: area.maxX - b, y: area.minY, width: b, height: b))
    }
    try data.write(to: extDir.appendingPathComponent("icon-\(size).png"))
}

// Toolbar icons are drawn as vector paths (not scaled symbols) so they stay sharp,
// and fill the whole canvas so they match other extensions' button size.

/// Down arrow with rounded caps, centred in `circle`.
func drawArrow(in circle: NSRect, color: NSColor) {
    let w = circle.width
    let lineWidth = w * 0.11
    let top = circle.midY + w * 0.25, bottom = circle.midY - w * 0.24
    let wing = w * 0.19
    let path = NSBezierPath()
    path.move(to: NSPoint(x: circle.midX, y: top))
    path.line(to: NSPoint(x: circle.midX, y: bottom))
    path.move(to: NSPoint(x: circle.midX - wing, y: bottom + wing))
    path.line(to: NSPoint(x: circle.midX, y: bottom))
    path.line(to: NSPoint(x: circle.midX + wing, y: bottom + wing))
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    path.stroke()
}

let toolbarSizes = [16, 19, 32, 38, 48, 64, 96, 128]
for size in toolbarSizes {
    // Idle: black outline on transparent, so Safari can tint and grey it out.
    let idle = png(size: size) { px in
        let stroke = px * 0.08
        let circle = NSRect(x: 0, y: 0, width: px, height: px).insetBy(dx: stroke / 2 + px * 0.02, dy: stroke / 2 + px * 0.02)
        let ring = NSBezierPath(ovalIn: circle)
        ring.lineWidth = stroke
        NSColor.black.setStroke()
        ring.stroke()
        drawArrow(in: circle, color: .black)
    }
    try idle.write(to: extDir.appendingPathComponent("toolbar-\(size).png"))

    // Active (on a video page): inverted — white arrow on a filled blue circle.
    let active = png(size: size) { px in
        let circle = NSRect(x: 0, y: 0, width: px, height: px).insetBy(dx: px * 0.02, dy: px * 0.02)
        rgb(0x2F7CF6).setFill()
        NSBezierPath(ovalIn: circle).fill()
        drawArrow(in: circle, color: .white)
    }
    try active.write(to: extDir.appendingPathComponent("toolbar-active-\(size).png"))
}

// App icon: macOS-style white rounded square, teal circles, play mark and download badge.
func drawAppIcon(_ px: CGFloat) {
    let inset = px * 0.098                     // macOS icon grid: 824/1024 artwork area
    let body = NSRect(x: 0, y: 0, width: px, height: px).insetBy(dx: inset, dy: inset)
    let radius = body.width * 0.225

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = px * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -px * 0.01)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    let gradient = NSGradient(starting: .white, ending: rgb(0xE6F4F5))!
    gradient.draw(in: path, angle: -90)

    let circles = body.insetBy(dx: body.width * 0.12, dy: body.height * 0.12)
    drawCircles(in: circles)

    // White play triangle on the front (light) circle.
    let d = circles.width * 0.62
    let front = NSRect(x: circles.minX + circles.width * 0.20, y: circles.minY, width: d, height: d)
    drawSymbol("play.fill", in: front.insetBy(dx: d * 0.30, dy: d * 0.28), colors: [.white])

    let badgeSize = body.width * 0.34
    drawDownloadBadge(in: NSRect(x: body.maxX - badgeSize - body.width * 0.07, y: body.minY + body.height * 0.07,
                                 width: badgeSize, height: badgeSize))
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let file = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(size: points * scale, draw: drawAppIcon).write(to: appIconDir.appendingPathComponent(file))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": file])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: appIconDir.appendingPathComponent("Contents.json"))
try #"{"info":{"author":"xcode","version":1}}"#.data(using: .utf8)!
    .write(to: appIconDir.deletingLastPathComponent().appendingPathComponent("Contents.json"))

print("Icons written.")
