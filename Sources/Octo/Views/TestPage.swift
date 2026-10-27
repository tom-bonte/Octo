import SwiftUI
import OctoCore

struct TestPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Page(title: "", subtitle: "Try gestures here to see what Octo recognizes. Actions don't run while this window is in front, so it's safe to practice.") {
            ConflictBanner()
            LiveTrackpadView()
            RecentLogView()
        }
        .onAppear { model.liveViewers += 1 }
        .onDisappear { model.liveViewers -= 1 }
    }
}

private struct LiveTrackpadView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let trackpad = model.liveTrackpad ?? model.trackpads.first
        let width = trackpad?.widthMM ?? 125
        let height = trackpad?.heightMM ?? 77
        let touches = model.liveTouches
        let pressed = model.livePressed && !touches.isEmpty
        let margin = model.config.tuning.edgeMargin

        Card {
            HStack {
                Text(trackpad?.name ?? "Trackpad").font(.headline)
                Spacer()
                legend(.accentColor, "Resting")
                legend(.orange, "Tapping")
                legend(.secondary, "Other")
                legend(.secondary, "Ignored", dashed: true)
            }

            Canvas { context, size in
                let padRect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
                let pad = Path(roundedRect: padRect, cornerRadius: 16, style: .continuous)
                context.fill(pad, with: .color(pressed ? Color.accentColor.opacity(0.08) : .primary.opacity(0.04)))

                // Edge zones: touches that start here are ignored.
                if margin > 0 {
                    let inner = CGRect(
                        x: size.width * margin, y: size.height * margin,
                        width: size.width * (1 - 2 * margin), height: size.height * (1 - 2 * margin)
                    )
                    var zone = pad
                    zone.addPath(Path(roundedRect: inner, cornerRadius: 10, style: .continuous))
                    context.fill(zone, with: .color(.primary.opacity(0.07)), style: FillStyle(eoFill: true))
                    context.stroke(Path(roundedRect: inner, cornerRadius: 10, style: .continuous),
                                   with: .color(.primary.opacity(0.2)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                context.stroke(pad, with: .color(pressed ? Color.accentColor.opacity(0.6) : .primary.opacity(0.15)), lineWidth: pressed ? 2 : 1)

                let scale = size.width / width
                let radius = (pressed ? 6.3 : 7.0) * scale
                for touch in touches {
                    let center = CGPoint(x: touch.x * scale, y: size.height - touch.y * scale)
                    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    if pressed {
                        // Pushed-down look: a ring around each finger.
                        context.stroke(Path(ellipseIn: rect.insetBy(dx: -7, dy: -7)), with: .color(.accentColor.opacity(0.55)), lineWidth: 3)
                    }
                    switch touch.role {
                    case .resting:
                        context.fill(Path(ellipseIn: rect), with: .color(.accentColor.opacity(0.85)))
                    case .tapping:
                        context.fill(Path(ellipseIn: rect), with: .color(.orange.opacity(0.85)))
                        context.stroke(Path(ellipseIn: rect.insetBy(dx: -6, dy: -6)), with: .color(.orange.opacity(0.5)), lineWidth: 2)
                    case .other:
                        context.fill(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.6)))
                    case .ignored:
                        context.stroke(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.8)),
                                       style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    }
                }
            }
            .aspectRatio(width / height, contentMode: .fit)
            .frame(maxWidth: 520)
            .overlay {
                if touches.isEmpty {
                    Text(model.trackpads.isEmpty ? "No trackpad found" : "Put your fingers on the trackpad")
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .topLeading) {
                if !touches.isEmpty {
                    HStack(spacing: 8) {
                        Text(touches.count == 1 ? "1 finger" : "\(touches.count) fingers")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if pressed {
                            Label("Pressed", systemImage: "cursorarrow.click")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.accentColor))
                                .fixedSize()
                        }
                    }
                    .padding(12)
                }
            }
            .frame(maxWidth: .infinity)

            if margin > 0 {
                Text("Touches that start in the shaded border are ignored, so a resting palm or thumb can't trigger gestures.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func legend(_ color: Color, _ text: String, dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            if dashed {
                Circle().strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2])).frame(width: 9, height: 9)
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
    }
}

private struct RecentLogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card {
            HStack {
                Text("Recent").font(.headline)
                Spacer()
                Button("Clear") { model.log.removeAll() }
                    .buttonStyle(.link)
                    .disabled(model.log.isEmpty)
            }
            if model.log.isEmpty {
                Text("Nothing yet. Try a gesture here, or in Chrome, Safari or Finder.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.log.prefix(8)) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: entry.symbol)
                                .foregroundStyle(entry.color)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title).font(.callout.weight(.medium))
                                Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.date, format: .dateTime.hour().minute().second())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}

struct TuningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let tuning = $model.config.tuning

        Card(spacing: 16) {
            HStack {
                Text("Timing and sensitivity").font(.headline)
                Spacer()
                Button("Restore Defaults") { model.config.tuning = Tuning() }
                    .disabled(model.config.tuning == Tuning())
            }

            section("Prevent accidental taps", symbol: "hand.raised")
            Grid(alignment: .topLeading, horizontalSpacing: 24, verticalSpacing: 18) {
                GridRow {
                    TuningSlider(title: "Pause after typing", help: "Taps don't count this soon after you type.",
                                 value: tuning.typingGuard, range: 0...1.5, step: 0.05, unit: .pause)
                    TuningSlider(title: "One-hand distance", help: "The tapping finger must be this close to a resting finger.",
                                 value: tuning.maxTapDistance, range: 20...100, step: 1, unit: .millimetres)
                    TuningSlider(title: "Ignored edges", help: "Touches starting this close to an edge are ignored (shaded on the Test tab).",
                                 value: tuning.edgeMargin, range: 0...0.30, step: 0.01, unit: .percent)
                }
            }

            Divider()

            section("Tap feel", symbol: "hand.tap")
            Grid(alignment: .topLeading, horizontalSpacing: 24, verticalSpacing: 18) {
                GridRow {
                    TuningSlider(title: "Tap speed", help: "A tap must lift within this time.",
                                 value: tuning.tapMaxDuration, range: 0.10...0.45, step: 0.01, unit: .milliseconds)
                    TuningSlider(title: "Tap wiggle", help: "How far the tapping finger may slide.",
                                 value: tuning.tapMaxMovement, range: 1...8, step: 0.5, unit: .millimetres)
                    TuningSlider(title: "Tap direction", help: "How far off sideways a tap may be.",
                                 value: tuning.maxTapAngle, range: 20...85, step: 1, unit: .degrees)
                }
                GridRow {
                    TuningSlider(title: "Rest before tapping", help: "How long fingers must be down to count as resting.",
                                 value: tuning.restMinDuration, range: 0...0.30, step: 0.01, unit: .milliseconds)
                    TuningSlider(title: "Resting wiggle", help: "How far resting fingers may drift during a tap.",
                                 value: tuning.restMaxMovement, range: 1...8, step: 0.5, unit: .millimetres)
                    TuningSlider(title: "Double-tap gap", help: "Time allowed between the two taps.",
                                 value: tuning.doubleTapInterval, range: 0.15...0.60, step: 0.01, unit: .milliseconds)
                }
            }
        }
    }

    private func section(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct TuningSlider: View {
    enum Unit { case milliseconds, millimetres, degrees, percent, pause }

    let title: String
    let help: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: Unit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout.weight(.medium))
                Spacer()
                Text(formatted).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var formatted: String {
        switch unit {
        case .milliseconds: "\(Int((value * 1000).rounded())) ms"
        case .millimetres: String(format: "%.1f mm", value)
        case .degrees: "\(Int(value.rounded()))°"
        case .percent: value < 0.005 ? "Off" : "\(Int((value * 100).rounded()))%"
        case .pause: value < 0.025 ? "Off" : "\(Int((value * 1000).rounded())) ms"
        }
    }
}
