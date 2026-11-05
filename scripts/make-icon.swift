// Renders the app icon (1024×1024 PNG). Used by scripts/make-icon.sh.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: macOS-style rounded square.
let inset: CGFloat = 100
let tile = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGradient(
    starting: NSColor(srgbRed: 0.17, green: 0.16, blue: 0.15, alpha: 1),
    ending: NSColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1)
)!.draw(in: tilePath, angle: -90)

// Three lamps: working, done, needs you.
let colors = [
    NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1),
    NSColor(srgbRed: 0.20, green: 0.80, blue: 0.35, alpha: 1),
    NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1),
]
let d: CGFloat = 200
let gap: CGFloat = 50
let total = 3 * d + 2 * gap
for (i, color) in colors.enumerated() {
    let rect = NSRect(x: (size - total) / 2 + CGFloat(i) * (d + gap), y: (size - d) / 2, width: d, height: d)

    // glow
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = color.withAlphaComponent(0.75)
    glow.shadowBlurRadius = 60
    glow.set()
    color.setFill()
    NSBezierPath(ovalIn: rect).fill()
    NSGraphicsContext.restoreGraphicsState()

    // lamp body
    let light = color.blended(withFraction: 0.55, of: .white)!
    let dark = color.blended(withFraction: 0.25, of: .black)!
    NSGradient(colors: [light, color, dark], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
        .draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: NSPoint(x: -0.35, y: 0.4))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
