import AppKit

struct IconSlot {
    let filename: String
    let pixels: Int
}

let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("stacker/Assets.xcassets/AppIcon.appiconset")

let slots = [
    IconSlot(filename: "app-icon-16.png", pixels: 16),
    IconSlot(filename: "app-icon-32.png", pixels: 32),
    IconSlot(filename: "app-icon-32@2x.png", pixels: 64),
    IconSlot(filename: "app-icon-128.png", pixels: 128),
    IconSlot(filename: "app-icon-128@2x.png", pixels: 256),
    IconSlot(filename: "app-icon-256.png", pixels: 256),
    IconSlot(filename: "app-icon-256@2x.png", pixels: 512),
    IconSlot(filename: "app-icon-512.png", pixels: 512),
    IconSlot(filename: "app-icon-512@2x.png", pixels: 1024)
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, size: CGFloat) -> NSRect {
    NSRect(x: x / 1024 * size, y: y / 1024 * size, width: width / 1024 * size, height: height / 1024 * size)
}

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat, size: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect(x, y, width, height, size: size), xRadius: radius / 1024 * size, yRadius: radius / 1024 * size)
}

func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat, size: CGFloat) {
    color.setStroke()
    path.lineWidth = max(1, width / 1024 * size)
    path.stroke()
}

func fill(_ path: NSBezierPath, color: NSColor) {
    color.setFill()
    path.fill()
}

func makeIcon(size: Int) throws -> Data {
    let side = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "StackerIcon", code: 1)
    }

    rep.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current?.shouldAntialias = true

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()

    let tile = roundedRect(78, 78, 868, 868, radius: 218, size: side)
    NSShadow().set()
    let tileGradient = NSGradient(colors: [
        color(52, 76, 96),
        color(18, 28, 39)
    ])
    tileGradient?.draw(in: tile, angle: 90)

    stroke(tile, color: color(255, 255, 255, 0.20), width: 18, size: side)

    let back = roundedRect(264, 304, 430, 298, radius: 58, size: side)
    fill(back, color: color(111, 132, 151, 0.72))
    stroke(back, color: color(255, 255, 255, 0.18), width: 10, size: side)

    let middle = roundedRect(224, 356, 470, 324, radius: 62, size: side)
    fill(middle, color: color(187, 199, 209, 0.88))
    stroke(middle, color: color(255, 255, 255, 0.42), width: 10, size: side)

    let front = roundedRect(184, 418, 510, 350, radius: 68, size: side)
    let frontGradient = NSGradient(colors: [
        color(248, 251, 253),
        color(218, 226, 233)
    ])
    frontGradient?.draw(in: front, angle: 90)
    stroke(front, color: color(255, 255, 255, 0.70), width: 12, size: side)

    let titleBar = roundedRect(214, 690, 450, 48, radius: 22, size: side)
    fill(titleBar, color: color(75, 96, 112, 0.16))

    for x in [246, 292, 338] as [CGFloat] {
        let dot = NSBezierPath(ovalIn: rect(x, 704, 18, 18, size: side))
        fill(dot, color: color(48, 68, 83, 0.38))
    }

    let marker = roundedRect(644, 382, 160, 318, radius: 80, size: side)
    let markerGradient = NSGradient(colors: [
        color(56, 211, 187),
        color(33, 136, 219)
    ])
    markerGradient?.draw(in: marker, angle: 90)
    stroke(marker, color: color(255, 255, 255, 0.55), width: 10, size: side)

    for y in [610, 536, 462] as [CGFloat] {
        let pill = roundedRect(684, y, 78, 34, radius: 17, size: side)
        fill(pill, color: color(255, 255, 255, 0.86))
    }

    let lowerGlow = roundedRect(164, 190, 570, 82, radius: 40, size: side)
    fill(lowerGlow, color: color(255, 255, 255, 0.10))

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "StackerIcon", code: 2)
    }
    return data
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for slot in slots {
    let data = try makeIcon(size: slot.pixels)
    try data.write(to: outputDirectory.appendingPathComponent(slot.filename), options: .atomic)
}
