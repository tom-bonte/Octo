// Octo's app icon: "every arm is a tool". A white octopus on a deep ocean-blue squircle, waving,
// each of its four arms fading into the colour of one tool (orange Keep Awake, violet Clean
// Keyboard, teal Copy Text, blue Gestures) and ending in a glowing pad.
// Usage: swift scripts/make-icon.swift out.png   (scripts/make-icon.sh builds the .icns)
import AppKit
import SwiftUI

let output = CommandLine.arguments[1]
let canvas: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let ns = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ns
let cg = ns.cgContext

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

// MARK: The squircle (Apple's continuous corners, on the macOS icon grid: 824 pt body, 100 pt margin)

let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let body = RoundedRectangle(cornerRadius: 185, style: .continuous).path(in: bodyRect).cgPath

cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.30))
cg.addPath(body)
cg.setFillColor(color(0x101A44))
cg.fillPath()
cg.restoreGState()

cg.saveGState()
cg.addPath(body)
cg.clip()
// Deep ocean, lighter at the top.
cg.drawLinearGradient(gradient([color(0x2B4590), color(0x16245C), color(0x0A1233)], [0, 0.55, 1]),
                      start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// A soft glow behind the octopus.
cg.drawRadialGradient(gradient([color(0x5B8CFF, 0.42), color(0x5B8CFF, 0)]),
                      startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                      endCenter: CGPoint(x: 512, y: 560), endRadius: 430, options: [])
// A faint sheen across the top.
cg.drawLinearGradient(gradient([color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)]),
                      start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])

// MARK: Arms

struct Arm {
    var p0, p1, p2, p3: CGPoint
    var tint: UInt32
}

func point(_ a: Arm, _ t: CGFloat) -> CGPoint {
    let m = 1 - t
    return CGPoint(
        x: m * m * m * a.p0.x + 3 * m * m * t * a.p1.x + 3 * m * t * t * a.p2.x + t * t * t * a.p3.x,
        y: m * m * m * a.p0.y + 3 * m * m * t * a.p1.y + 3 * m * t * t * a.p2.y + t * t * t * a.p3.y)
}

func direction(_ a: Arm, _ t: CGFloat) -> CGVector {
    let m = 1 - t
    let dx = 3 * m * m * (a.p1.x - a.p0.x) + 6 * m * t * (a.p2.x - a.p1.x) + 3 * t * t * (a.p3.x - a.p2.x)
    let dy = 3 * m * m * (a.p1.y - a.p0.y) + 6 * m * t * (a.p2.y - a.p1.y) + 3 * t * t * (a.p3.y - a.p2.y)
    let length = max(hypot(dx, dy), 0.0001)
    return CGVector(dx: dx / length, dy: dy / length)
}

/// A tapering tentacle outline: wide where it leaves the head, narrower at the tip.
func outline(_ a: Arm, base: CGFloat, tip: CGFloat) -> CGPath {
    var left: [CGPoint] = [], right: [CGPoint] = []
    let steps = 160
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let p = point(a, t), d = direction(a, t)
        let half = (base + (tip - base) * pow(t, 0.8)) / 2
        left.append(CGPoint(x: p.x - d.dy * half, y: p.y + d.dx * half))
        right.append(CGPoint(x: p.x + d.dy * half, y: p.y - d.dx * half))
    }
    let path = CGMutablePath()
    path.addLines(between: left + right.reversed())
    path.closeSubpath()
    return path
}

let pale = color(0xF4F6FF)
func mirrored(_ a: Arm, tint: UInt32) -> Arm {
    func m(_ p: CGPoint) -> CGPoint { CGPoint(x: canvas - p.x, y: p.y) }
    return Arm(p0: m(a.p0), p1: m(a.p1), p2: m(a.p2), p3: m(a.p3), tint: tint)
}
// Left side; the right side mirrors it. The outer arms curl up, as if waving.
let outer = Arm(p0: CGPoint(x: 440, y: 500), p1: CGPoint(x: 350, y: 350), p2: CGPoint(x: 180, y: 320), p3: CGPoint(x: 200, y: 486), tint: 0xFF9F1C)
let inner = Arm(p0: CGPoint(x: 482, y: 470), p1: CGPoint(x: 474, y: 344), p2: CGPoint(x: 376, y: 340), p3: CGPoint(x: 392, y: 208), tint: 0x8F8BFF)
let arms = [
    outer,                              // Keep Awake: orange
    inner,                              // Clean Keyboard: violet
    mirrored(inner, tint: 0x35D3CC),    // Copy Text: teal
    mirrored(outer, tint: 0x3D9BFF),    // Gestures: blue
]
let armWidths: (base: CGFloat, tip: CGFloat) = (100, 52)

for arm in arms {
    let path = outline(arm, base: armWidths.base, tip: armWidths.tip)
    // Arm: white near the head, the tool's colour toward the tip.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(0x000000, 0.28))
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    cg.addPath(path)
    cg.clip()
    cg.drawLinearGradient(gradient([pale, pale, color(arm.tint)], [0, 0.35, 1]),
                          start: arm.p0, end: arm.p3, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    cg.endTransparencyLayer()
    cg.restoreGState()
}

// Glowing pads at the tips.
for arm in arms {
    let r: CGFloat = 40
    let pad = CGRect(x: arm.p3.x - r, y: arm.p3.y - r, width: r * 2, height: r * 2)
    cg.saveGState()
    cg.setShadow(offset: .zero, blur: 34, color: color(arm.tint, 0.85))
    cg.setFillColor(color(arm.tint))
    cg.fillEllipse(in: pad)
    cg.restoreGState()
    cg.saveGState()
    cg.addEllipse(in: pad)
    cg.clip()
    cg.drawRadialGradient(gradient([color(0xFFFFFF, 0.55), color(0xFFFFFF, 0)]),
                          startCenter: CGPoint(x: arm.p3.x - 12, y: arm.p3.y + 14), startRadius: 0,
                          endCenter: CGPoint(x: arm.p3.x - 12, y: arm.p3.y + 14), endRadius: r * 0.9, options: [])
    cg.restoreGState()
}

// MARK: Head

let headRect = CGRect(x: 302, y: 418, width: 420, height: 396)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, 0.35))
cg.setFillColor(pale)
cg.fillEllipse(in: headRect)
cg.restoreGState()
cg.saveGState()
cg.addEllipse(in: headRect)
cg.clip()
cg.drawLinearGradient(gradient([color(0xFFFFFF), color(0xDDE4FF)]),
                      start: CGPoint(x: 512, y: headRect.maxY), end: CGPoint(x: 512, y: headRect.minY), options: [])
// Gloss on the upper left of the head.
cg.drawRadialGradient(gradient([color(0xFFFFFF, 0.9), color(0xFFFFFF, 0)]),
                      startCenter: CGPoint(x: 430, y: 740), startRadius: 0,
                      endCenter: CGPoint(x: 430, y: 740), endRadius: 120, options: [])
cg.restoreGState()

// Eyes, with a glint.
for x: CGFloat in [452, 572] {
    cg.setFillColor(color(0x121A3E))
    cg.fillEllipse(in: CGRect(x: x - 29, y: 566, width: 58, height: 66))
    cg.setFillColor(color(0xFFFFFF))
    cg.fillEllipse(in: CGRect(x: x - 4, y: 603, width: 20, height: 20))
}
// Cheeks.
for x: CGFloat in [404, 620] {
    cg.setFillColor(color(0xFF8FA8, 0.28))
    cg.fillEllipse(in: CGRect(x: x - 26, y: 530, width: 52, height: 30))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
