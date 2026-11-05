import AppKit

/// Draws the row of lamps shown in the menu bar.
enum LightIcon {
    static let diameter: CGFloat = 10
    static let spacing: CGFloat = 4
    static let height: CGFloat = 18

    static func color(for light: Light) -> NSColor {
        switch light {
        case .working: return NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1)
        case .done: return NSColor(srgbRed: 0.20, green: 0.80, blue: 0.35, alpha: 1)
        case .attention: return NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1)
        }
    }

    /// Menu bar image: one lamp per session, or a hollow template circle when idle.
    static func statusImage(for lights: [Light]) -> NSImage {
        guard !lights.isEmpty else { return emptyImage() }

        let width = CGFloat(lights.count) * diameter + CGFloat(lights.count - 1) * spacing
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            for (i, light) in lights.enumerated() {
                let x = CGFloat(i) * (diameter + spacing)
                let rect = NSRect(x: x, y: (height - diameter) / 2, width: diameter, height: diameter)
                drawLamp(in: rect, color: color(for: light))
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// A single lamp, used next to menu items.
    static func dot(for light: Light, diameter d: CGFloat = 10) -> NSImage {
        let size = d + 2
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            drawLamp(in: NSRect(x: 1, y: 1, width: d, height: d), color: color(for: light))
            return true
        }
    }

    private static func drawLamp(in rect: NSRect, color: NSColor) {
        let path = NSBezierPath(ovalIn: rect)
        let light = color.blended(withFraction: 0.45, of: .white) ?? color
        let dark = color.blended(withFraction: 0.15, of: .black) ?? color
        NSGradient(colors: [light, color, dark], atLocations: [0, 0.55, 1], colorSpace: .sRGB)?
            .draw(in: path, relativeCenterPosition: NSPoint(x: -0.35, y: 0.35))

        dark.withAlphaComponent(0.6).setStroke()
        let rim = NSBezierPath(ovalIn: rect.insetBy(dx: 0.25, dy: 0.25))
        rim.lineWidth = 0.5
        rim.stroke()
    }

    private static func emptyImage() -> NSImage {
        let image = NSImage(size: NSSize(width: diameter + 2, height: height), flipped: false) { _ in
            let rect = NSRect(x: 1, y: (height - diameter) / 2, width: diameter, height: diameter)
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
            path.lineWidth = 1.5
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
