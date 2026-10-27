import SwiftUI
import OctoCore

/// The big status card at the top of a tool page.
struct ToolHero<Actions: View>: View {
    let symbol: String
    let tint: Color
    let isOn: Bool
    let title: String
    let detail: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().fill(isOn ? tint : tint.opacity(0.15))
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : tint)
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.bold())
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            actions
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isOn ? tint.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isOn ? tint.opacity(0.45) : Color.primary.opacity(0.08))
        )
    }
}

struct KeepAwakePage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Page(title: "Keep Awake", subtitle: "Stops your Mac from going to sleep until you turn it off.") {
            ToolHero(
                symbol: model.keepAwake ? "cup.and.saucer.fill" : "cup.and.saucer",
                tint: .orange,
                isOn: model.keepAwake,
                title: model.keepAwake ? "Your Mac is staying awake" : "Your Mac can sleep as usual",
                detail: model.keepAwake
                    ? "It won't go to sleep until you turn this off."
                    : "Turn this on for a long download, a presentation, or anything that shouldn't be interrupted."
            ) {
                Button(model.keepAwake ? "Turn Off" : "Keep Awake") { model.setKeepAwake(!model.keepAwake) }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(model.keepAwake ? .gray : .orange)
            }

            Card {
                SettingRow(title: "Screen stays on too", caption: "When off, the Mac stays awake but the screen can still turn off.") {
                    Toggle("Screen stays on too", isOn: $model.config.awakeKeepsScreenOn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            Label {
                Text("Also one click in Octo's menu bar panel. While it's on, a small cup shows on Octo's menu bar icon. It starts off each time Octo starts.")
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

struct CleanKeyboardPage: View {
    @Environment(AppModel.self) private var model
    @State private var failed = false

    var body: some View {
        Page(title: "Clean Keyboard", subtitle: "Blocks the keyboard and trackpad gestures so you can wipe them clean.") {
            ToolHero(
                symbol: "keyboard",
                tint: .indigo,
                isOn: model.keyboardLocked,
                title: model.keyboardLocked ? "Keyboard locked" : "Ready to clean",
                detail: "Keys, scrolling and multi-finger swipes are ignored while it's on. The pointer still moves, so you can unlock."
            ) {
                Button("Lock Keyboard") { failed = !model.lockKeyboard() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(model.keyboardLocked)
            }
            .onChange(of: model.accessibilityGranted) { failed = false }

            if failed {
                HStack(spacing: 10) {
                    Text("Couldn't lock the keyboard: Octo needs Accessibility permission.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Button("Allow Access…") { Permissions.requestAccessibility() }
                }
            }

            Card {
                Text("How to unlock").font(.headline)
                unlockRow("hand.point.up.left.fill", "Hold the “Hold to unlock” button on screen for a second. A quick click or a wipe won't do it.")
                unlockRow("timer", "It unlocks by itself after 5 minutes.")
                unlockRow("lock.display", "It also unlocks if the screen locks, the Mac sleeps, or Octo quits.")
            }

            Label {
                Text("Avoid the Touch ID button while cleaning: macOS doesn't let apps block it.")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func unlockRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.indigo)
                .frame(width: 22)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CopyTextPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Page(title: "Copy Text", subtitle: "Copy the text from anything on screen: images, PDFs, paused videos, screen shares.") {
            ToolHero(
                symbol: "text.viewfinder",
                tint: .teal,
                isOn: false,
                title: "Drag a box, get the text",
                detail: "Read on your Mac, offline. A box around a QR code copies its link instead."
            ) {
                Button("Copy Text Now") { TextGrabber.shared.start() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
            }

            if !model.screenRecordingGranted {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "lock.shield").font(.system(size: 22)).foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Copy Text needs Screen Recording permission").font(.headline)
                        Text("In System Settings → Privacy & Security → Screen & System Audio Recording, turn on Octo. macOS may ask to quit and reopen Octo. Octo only looks at the box you draw, and only when you start it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 6) {
                        Button("Open System Settings") { TextGrabber.openPermissionSettings() }
                        Button("Check Again") { model.refreshScreenRecording() }.buttonStyle(.link)
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.35)))
            }

            Card {
                SettingRow(
                    title: "Shortcut",
                    caption: model.hotkeyTaken
                        ? "Another app already uses this shortcut. Click it to pick a different one."
                        : (model.config.copyTextHotkey.isSet ? "Press it anywhere to start Copy Text. Click to change." : "No shortcut. Click to record one.")
                ) {
                    HStack(spacing: 6) {
                        ShortcutRecorder(combo: $model.config.copyTextHotkey, autoStart: false, global: true)
                        if model.config.copyTextHotkey.isSet {
                            Button {
                                model.config.copyTextHotkey = .unset
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove the shortcut")
                        }
                    }
                }
                Divider()
                SettingRow(title: "Keep line breaks", caption: "When off, the lines are joined into one paragraph.") {
                    Toggle("Keep line breaks", isOn: $model.config.copyTextKeepsLineBreaks)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            Label {
                Text("Also a tile in Octo's menu bar panel, and an action you can put on any gesture: Gestures → Add Gesture → Copy text from screen.")
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .onAppear { model.refreshScreenRecording() }
    }
}
