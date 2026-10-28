// The picture behind the icons in Octo's disk image window: drag Octo to Applications, and what
// to do when macOS blocks the first launch. scripts/release.sh runs this.
// Usage: swift scripts/make-dmg-background.swift <output folder>   (writes background.tiff)
// The window is 660×440 points; the tiff holds a normal and a Retina version. Finder always shows
// a window with a background picture in light mode, so this is designed for light mode only.
import AppKit

let folder = CommandLine.arguments[1]
let size = CGSize(width: 660, height: 440)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let ink = rgb(0x1D1D1F)
let soft = rgb(0x6E6E73)
let accent = rgb(0x0A84FF)

/// Draws with the origin at the top left, like Finder's icon positions.
func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let base = NSGraphicsContext(bitmapImageRep: rep)!
    let c = base.cgContext
    c.translateBy(x: 0, y: size.height)
    c.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
    NSGraphicsContext.current?.imageInterpolation = .high

    // Background: Apple's light grey with faint glows in Octo's tool colours.
    rgb(0xF5F5F7).setFill()
    NSRect(origin: .zero, size: size).fill()
    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    func glow(_ hex: UInt32, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ a: CGFloat) {
        let g = CGGradient(colorsSpace: srgb, colors: [rgb(hex, a).cgColor, rgb(hex, 0).cgColor] as CFArray, locations: [0, 1])!
        c.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
    }
    glow(0x3D7BFF, 560, 40, 300, 0.10)
    glow(0x8F8BFF, 640, 300, 260, 0.07)
    glow(0x35D3CC, 60, 120, 260, 0.06)
    glow(0xFF9F1C, 120, 430, 240, 0.05)

    func text(_ s: NSAttributedString, centeredAt y: CGFloat) {
        let w = s.size().width
        s.draw(at: NSPoint(x: (size.width - w) / 2, y: y))
    }
    func attributed(_ s: String, _ pt: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSMutableAttributedString {
        NSMutableAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: pt, weight: weight), .foregroundColor: color])
    }

    // Heading.
    text(attributed("Drag Octo into Applications", 21, .semibold, ink), centeredAt: 26)

    // Arrow between the two icons (the icons sit at x 170 and 490, y 135).
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 250, y: 135))
    arrow.line(to: NSPoint(x: 400, y: 135))
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    accent.setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 392, y: 123))
    head.line(to: NSPoint(x: 410, y: 135))
    head.line(to: NSPoint(x: 392, y: 147))
    head.lineWidth = 4
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // The steps, on a white card under the icons.
    let card = NSRect(x: 40, y: 234, width: 580, height: 192)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: 2), blur: 10, color: NSColor.black.withAlphaComponent(0.08).cgColor)
    NSColor.white.withAlphaComponent(0.9).setFill()
    NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14).fill()
    c.restoreGState()

    let steps: [(String, [String])] = [
        ("Drag Octo onto the Applications folder.", []),
        ("Open Octo from your Applications folder.", []),
        ("Does macOS say it can’t open Octo? Open System Settings › Privacy & Security, scroll down and click Open Anyway. You only do this once.",
         ["System Settings › Privacy & Security", "Open Anyway"]),
    ]
    var y = card.minY + 20
    let textX = card.minX + 58
    let textWidth = card.maxX - 22 - textX
    for (i, step) in steps.enumerated() {
        let circle = NSRect(x: card.minX + 22, y: y - 1, width: 24, height: 24)
        accent.setFill()
        NSBezierPath(ovalIn: circle).fill()
        let number = attributed("\(i + 1)", 13, .bold, .white)
        number.draw(at: NSPoint(x: circle.midX - number.size().width / 2, y: circle.midY - number.size().height / 2))

        let line = attributed(step.0, 14, .regular, ink)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        line.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: line.length))
        for bold in step.1 {
            let range = (step.0 as NSString).range(of: bold)
            line.addAttribute(.font, value: NSFont.systemFont(ofSize: 14, weight: .semibold), range: range)
        }
        let height = line.boundingRect(with: NSSize(width: textWidth, height: 200), options: [.usesLineFragmentOrigin]).height
        line.draw(with: NSRect(x: textX, y: y + 2, width: textWidth, height: height), options: [.usesLineFragmentOrigin])
        y += max(height, 22) + 16
    }
    // A quiet note on why, at the bottom of the card.
    let why = attributed("Octo is free and open source, but not notarized by Apple yet. That’s why macOS asks.", 11.5, .regular, soft)
    text(why, centeredAt: card.maxY - 28)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("octo-dmg-\(getpid())")
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
var files: [String] = []
for scale in [1, 2] as [CGFloat] {
    let path = tmp.appendingPathComponent(scale == 1 ? "background.png" : "background@2x.png").path
    try! render(scale: scale).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    files.append(path)
}
// One tiff with both sizes, so the window is sharp on Retina screens.
let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck"] + files + ["-out", folder + "/background.tiff"]
try! tiffutil.run()
tiffutil.waitUntilExit()
try? FileManager.default.removeItem(at: tmp)
print("wrote \(folder)/background.tiff")
