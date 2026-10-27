import SwiftUI
import OctoCore

/// The Gestures tool: an on/off switch and four tabs (the gesture list, apps, tuning, testing).
struct GesturesToolPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gestures").font(.system(size: 26, weight: .bold))
                    Text("Trackpad gestures for your browser, Finder and other apps.")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle(model.config.enabled ? "On" : "Paused", isOn: $model.config.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .help("Turn every gesture on or off")
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)

            Picker("Section", selection: $model.gestureTab) {
                ForEach(GestureTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                switch model.gestureTab {
                case .list: GesturesPage()
                case .apps: AppsPage()
                case .tuning: TuningPage()
                case .test: TestPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Gesture timing, accidental-tap protection, click handling and the trackpads in use.
struct TuningPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Page(title: "", subtitle: "Make gestures easier to trigger, or harder to set off by accident. Changes apply right away; try them on the Test tab.") {
            TuningView()

            Card {
                SettingRow(
                    title: "Block the extra click from Tap to click",
                    caption: "With Tap to click on, macOS also clicks when you tap for a gesture, which could hit a link under the pointer. Octo removes that click."
                ) {
                    Toggle("Block the extra click", isOn: $model.config.blockTapClicks).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingRow(
                    title: "Show which gesture ran",
                    caption: "A small bubble near the bottom of the screen names the gesture and what it did. Handy while you learn the gestures, or when you record a demo."
                ) {
                    Toggle("Show which gesture ran", isOn: $model.config.showGestureHints).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingRow(
                    title: "Show your fingers on screen",
                    caption: "A small live trackpad in the corner of the screen, so a screen recording shows the gestures you make. Drag it wherever you like."
                ) {
                    Toggle("Show your fingers on screen", isOn: $model.config.showFingersOverlay).labelsHidden().toggleStyle(.switch)
                }
            }

            Card {
                Text("Trackpads").font(.headline)
                if model.trackpads.isEmpty {
                    Text(TrackpadManager.shared.isAvailable
                         ? "No trackpad found. Connect a Magic Trackpad, or restart Octo."
                         : "This version of macOS doesn't let Octo read the trackpad.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.trackpads) { trackpad in
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.and.hand.point.up.left")
                                .foregroundStyle(.tint)
                                .frame(width: 22)
                            Text(trackpad.name)
                            Spacer()
                            Text(String(format: "%.0f × %.0f mm", trackpad.widthMM, trackpad.heightMM))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}
