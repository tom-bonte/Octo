import AppKit

/// Octo's menu bar icon: a small octopus (faded while gestures are paused),
/// with a coffee cup badge while keep-awake is on.
enum StatusIcon {
    static let height: CGFloat = 18

    static func image(gesturesOn: Bool, awake: Bool) -> NSImage {
        let cup = awake
            ? NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8.5, weight: .bold))
            : nil
        let width = height + (cup.map { $0.size.width * 0.6 } ?? 0)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            guard let context = NSGraphicsContext.current else { return false }
            context.saveGraphicsState()
            if !gesturesOn { context.cgContext.setAlpha(0.45) }
            // One layer, so overlapping parts fade evenly.
            context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            drawOctopus()
            context.cgContext.endTransparencyLayer()
            context.restoreGraphicsState()

            if let cup {
                let cupRect = NSRect(x: rect.width - cup.size.width, y: 0, width: cup.size.width, height: cup.size.height)
                // A thin gap around the cup so it reads as a separate badge.
                cup.draw(in: cupRect.insetBy(dx: -1.5, dy: -1.5), from: .zero, operation: .destinationOut, fraction: 1)
                cup.draw(in: cupRect)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = awake ? "Octo, keeping your Mac awake" : "Octo"
        return image
    }

    /// An 18×18 point octopus, like the app icon: a round head with two eyes, the outer arms
    /// curling up (waving), the inner arms hanging down, each arm ending in a small pad.
    private static func drawOctopus() {
        NSColor.black.set()
        let arms: [(NSPoint, NSPoint, NSPoint, NSPoint)] = [
            (NSPoint(x: 7.0, y: 8.6), NSPoint(x: 5.4, y: 5.6), NSPoint(x: 1.8, y: 5.0), NSPoint(x: 2.0, y: 8.4)),
            (NSPoint(x: 8.2, y: 8.0), NSPoint(x: 8.0, y: 5.4), NSPoint(x: 6.4, y: 5.0), NSPoint(x: 6.6, y: 2.4)),
            (NSPoint(x: 9.8, y: 8.0), NSPoint(x: 10.0, y: 5.4), NSPoint(x: 11.6, y: 5.0), NSPoint(x: 11.4, y: 2.4)),
            (NSPoint(x: 11.0, y: 8.6), NSPoint(x: 12.6, y: 5.6), NSPoint(x: 16.2, y: 5.0), NSPoint(x: 16.0, y: 8.4)),
        ]
        for (start, c1, c2, end) in arms {
            let path = NSBezierPath()
            path.move(to: start)
            path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
            path.lineWidth = 1.8
            path.lineCapStyle = .round
            path.stroke()
            NSBezierPath(ovalIn: NSRect(x: end.x - 1.45, y: end.y - 1.45, width: 2.9, height: 2.9)).fill()
        }
        NSBezierPath(ovalIn: NSRect(x: 4.4, y: 7.4, width: 9.2, height: 9.4)).fill()

        // Eyes are cut out of the head.
        guard let context = NSGraphicsContext.current else { return }
        let previous = context.compositingOperation
        context.compositingOperation = .clear
        for x in [7.3, 10.7] {
            NSBezierPath(ovalIn: NSRect(x: x - 1.15, y: 11.0, width: 2.3, height: 2.6)).fill()
        }
        context.compositingOperation = previous
    }
}
