import SwiftUI
import OctoCore

/// A small trackpad drawing of a gesture: filled dots are resting fingers,
/// orange is the tapping finger, and a pressed row of dots is a click.
/// With `animated`, it plays the gesture in a loop (taps tap, clicks press down).
struct GestureDiagram: View {
    let gesture: GestureKind
    var animated = false

    static let loopSeconds = 1.8

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                GestureCanvas(gesture: gesture, phase: t.truncatingRemainder(dividingBy: Self.loopSeconds) / Self.loopSeconds)
            }
        } else {
            GestureCanvas(gesture: gesture, phase: nil)
        }
    }
}

private struct GestureCanvas: View {
    let gesture: GestureKind
    /// 0...1 through the animation loop, or nil for the still drawing.
    let phase: Double?

    private static let tapColor = Color.orange

    var body: some View {
        Canvas { context, size in
            draw(&context, size: size)
        }
        .accessibilityLabel(gesture.title)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        let pad = Path(roundedRect: rect, cornerRadius: min(size.width, size.height) * 0.16, style: .continuous)
        context.fill(pad, with: .color(.primary.opacity(0.05)))
        context.stroke(pad, with: .color(.primary.opacity(0.16)), lineWidth: 1)

        let r = max(4, size.height * 0.105)
        let gap = r * 2.7
        let cy = size.height * 0.5

        switch gesture {
        case let .fixTap(resting, side, taps):
            let tapGap = gap * 1.3
            let span = CGFloat(resting - 1) * gap + tapGap
            let x0 = size.width / 2 - span / 2
            var restXs: [CGFloat] = []
            let tapX: CGFloat
            if side == .left {
                tapX = x0
                for i in 0..<resting { restXs.append(x0 + tapGap + CGFloat(i) * gap) }
            } else {
                for i in 0..<resting { restXs.append(x0 + CGFloat(i) * gap) }
                tapX = x0 + span
            }
            for x in restXs {
                drawRestingFinger(&context, at: CGPoint(x: x, y: cy), radius: r)
            }
            let tapCenter = CGPoint(x: tapX, y: taps == 2 ? cy - r * 0.35 : cy)

            if let phase {
                // Moments when the tapping finger is down.
                let touches: [ClosedRange<Double>] = taps == 2 ? [0.20...0.32, 0.44...0.56] : [0.28...0.44]
                if let touch = touches.first(where: { $0.contains(phase) }) {
                    let progress = (phase - touch.lowerBound) / (touch.upperBound - touch.lowerBound)
                    context.fill(Path(ellipseIn: circle(tapCenter, r)), with: .color(Self.tapColor))
                    context.stroke(
                        Path(ellipseIn: circle(tapCenter, r * (1.15 + 1.1 * progress))),
                        with: .color(Self.tapColor.opacity(0.75 * (1 - progress))),
                        lineWidth: 1.6
                    )
                } else {
                    // Where the finger will tap.
                    context.stroke(
                        Path(ellipseIn: circle(tapCenter, r)),
                        with: .color(Self.tapColor.opacity(0.5)),
                        style: StrokeStyle(lineWidth: 1.3, dash: [2.5, 2.5])
                    )
                }
            } else {
                for ring in 0..<taps {
                    let ringRadius = r * (1.6 + CGFloat(ring) * 0.55)
                    context.stroke(
                        Path(ellipseIn: circle(tapCenter, ringRadius)),
                        with: .color(Self.tapColor.opacity(0.55 - Double(ring) * 0.22)),
                        lineWidth: 1.3
                    )
                }
                context.stroke(Path(ellipseIn: circle(tapCenter, r)), with: .color(Self.tapColor), lineWidth: 2)
                context.fill(Path(ellipseIn: circle(tapCenter, r * 0.42)), with: .color(Self.tapColor))
            }
            if taps == 2 {
                let label = Text("2×").font(.system(size: max(8, r * 1.15), weight: .bold)).foregroundColor(Self.tapColor)
                context.draw(label, at: CGPoint(x: tapCenter.x, y: tapCenter.y + r * 2.75))
            }

        case let .fingerTap(fingers):
            let span = CGFloat(fingers - 1) * gap
            let x0 = size.width / 2 - span / 2
            var down = false
            var progress = 0.0
            if let phase, (0.30...0.46).contains(phase) {
                down = true
                progress = (phase - 0.30) / 0.16
            }
            for i in 0..<fingers {
                let middle = i > 0 && i < fingers - 1
                let center = CGPoint(x: x0 + CGFloat(i) * gap, y: cy - (middle ? r * 0.45 : 0))
                if phase == nil {
                    context.stroke(Path(ellipseIn: circle(center, r * 1.5)), with: .color(Self.tapColor.opacity(0.45)), lineWidth: 1.2)
                    context.stroke(Path(ellipseIn: circle(center, r)), with: .color(Self.tapColor), lineWidth: 2)
                    context.fill(Path(ellipseIn: circle(center, r * 0.42)), with: .color(Self.tapColor))
                } else if down {
                    context.fill(Path(ellipseIn: circle(center, r)), with: .color(Self.tapColor))
                    context.stroke(Path(ellipseIn: circle(center, r * (1.15 + 0.9 * progress))),
                                   with: .color(Self.tapColor.opacity(0.75 * (1 - progress))), lineWidth: 1.5)
                } else {
                    context.stroke(Path(ellipseIn: circle(center, r)), with: .color(Self.tapColor.opacity(0.5)),
                                   style: StrokeStyle(lineWidth: 1.3, dash: [2.5, 2.5]))
                }
            }

        case let .fingerClick(fingers):
            // 0 = resting on the pad, 1 = fully pressed.
            var press = 0.0
            if let phase, (0.35...0.62).contains(phase) {
                press = sin((phase - 0.35) / 0.27 * .pi)
            }
            let span = CGFloat(fingers - 1) * gap
            let x0 = size.width / 2 - span / 2
            let fingerY = cy - r * 0.5 + r * 0.3 * press
            for i in 0..<fingers {
                let middle = i > 0 && i < fingers - 1
                let center = CGPoint(x: x0 + CGFloat(i) * gap, y: fingerY - (middle ? r * 0.45 : 0))
                context.fill(Path(ellipseIn: circle(center, r * 1.25)), with: .color(Color.accentColor.opacity(0.18 + 0.2 * press)))
                if press > 0.05 {
                    context.stroke(Path(ellipseIn: circle(center, r * (1.35 + 0.35 * press))),
                                   with: .color(Color.accentColor.opacity(0.6 * press)), lineWidth: 1.5)
                }
                drawRestingFinger(&context, at: center, radius: r * (1 - 0.1 * press))
            }
            // Downward chevron: "press".
            var chevron = Path()
            let chevronY = cy - r * 0.5 + r * 2.0 + r * 0.4 * press
            chevron.move(to: CGPoint(x: size.width / 2 - r * 0.9, y: chevronY))
            chevron.addLine(to: CGPoint(x: size.width / 2, y: chevronY + r * 0.75))
            chevron.addLine(to: CGPoint(x: size.width / 2 + r * 0.9, y: chevronY))
            let chevronOpacity = phase == nil ? 1 : 0.4 + 0.6 * press
            context.stroke(chevron, with: .color(.accentColor.opacity(chevronOpacity)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    private func drawRestingFinger(_ context: inout GraphicsContext, at center: CGPoint, radius: CGFloat) {
        context.fill(Path(ellipseIn: circle(center, radius)), with: .color(.accentColor))
        context.fill(
            Path(ellipseIn: circle(CGPoint(x: center.x - radius * 0.28, y: center.y - radius * 0.3), radius * 0.32)),
            with: .color(.white.opacity(0.35))
        )
    }
}
