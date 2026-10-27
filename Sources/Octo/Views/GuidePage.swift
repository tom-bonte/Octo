import AppKit
import SwiftUI
import OctoCore

/// "How Octo works": what the app is, how to get started, and what each tool does.
/// Opened from the ? in the menu bar panel, the top of the Settings sidebar, and on first launch.
struct GuidePage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                hero
                gettingStarted

                VStack(alignment: .leading, spacing: 14) {
                    Text("The tools").font(.title2.bold())
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), alignment: .top)],
                        spacing: 16
                    ) {
                        gesturesCard
                        keepAwakeCard
                        cleanKeyboardCard
                        copyTextCard
                    }
                }

                tips

                if AppInfo.supportURL != nil {
                    SupportCard()
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Welcome

    private var hero: some View {
        HStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 92, height: 92)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text("Octo")
                    .font(.system(size: 34, weight: .bold))
                Text("Small helpers for your Mac, all in one octopus in the menu bar. Each arm is a tool: trackpad gestures, keeping your Mac awake, cleaning the keyboard, and copying text from anything on screen.")
                    .font(.title3)
                    .opacity(0.9)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.19, green: 0.73, blue: 0.82), Color(red: 0.11, green: 0.29, blue: 0.70)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
        )
    }

    // MARK: Getting started

    private var gettingStarted: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Getting started").font(.title2.bold())
            HStack(alignment: .top, spacing: 14) {
                StartStep(number: 1, title: "Allow Octo", caption: "macOS asks once for Accessibility, so Octo can send shortcuts and handle clicks.") {
                    if model.accessibilityGranted {
                        Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow Access…") { Permissions.requestAccessibility() }
                    }
                }
                StartStep(number: 2, title: "Find the octopus", caption: "Click it in the menu bar for one-click tiles: Keep Awake, Clean Keyboard, Copy Text and Gestures.") {
                    HStack(spacing: 8) {
                        Image(nsImage: StatusIcon.image(gesturesOn: true, awake: false))
                        Text("in your menu bar").font(.callout).foregroundStyle(.secondary)
                    }
                }
                StartStep(number: 3, title: "Try a gesture", caption: "Practice on the Test tab: you see your fingers live, and nothing actually happens.") {
                    Button("Open Test") {
                        model.gestureTab = .test
                        model.page = .gestures
                    }
                }
            }

            Card {
                SettingRow(title: "Open Octo when you log in", caption: model.launchAtLoginNote ?? "So your tools are always in the menu bar. You can change this later under General.") {
                    Toggle("Open Octo when you log in", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
        }
    }

    // MARK: Tools

    private var gesturesCard: some View {
        let shown = model.sortedBindings.filter(\.enabled).prefix(4)
        return GuideToolCard(
            symbol: "hand.tap.fill",
            tint: .blue,
            title: "Gestures",
            summary: "Tap and click with several fingers to switch tabs, open links in new tabs, reload and more.",
            steps: [
                "Rest a finger on the trackpad and keep it still.",
                "Tap or click with your other fingers, as shown above.",
                "Change gestures, or add new ones, under Gestures in Settings.",
            ],
            primary: ("Practice", { model.gestureTab = .test; model.page = .gestures }),
            settings: { model.gestureTab = .list; model.page = .gestures }
        ) {
            // Wraps onto more rows when the card is narrow.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 8, alignment: .top)], alignment: .leading, spacing: 10) {
                ForEach(Array(shown)) { binding in
                    VStack(spacing: 5) {
                        GestureDiagram(gesture: binding.gesture, animated: true)
                            .frame(width: 62, height: 40)
                        Text(binding.action.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(width: 66)
                    }
                }
            }
        }
    }

    private var keepAwakeCard: some View {
        GuideToolCard(
            symbol: model.keepAwake ? "cup.and.saucer.fill" : "cup.and.saucer",
            tint: .orange,
            title: "Keep Awake",
            summary: "Stops your Mac from going to sleep: for long downloads, presentations, or anything that shouldn't stop halfway.",
            steps: [
                "Click Keep Awake in the octopus panel.",
                "A small cup shows on the octopus while your Mac stays awake.",
                "Click it again to let your Mac sleep as usual.",
            ],
            primary: (model.keepAwake ? "Turn Off" : "Keep Awake", { model.setKeepAwake(!model.keepAwake) }),
            settings: { model.page = .keepAwake }
        ) { EmptyView() }
    }

    private var cleanKeyboardCard: some View {
        GuideToolCard(
            symbol: "keyboard",
            tint: .indigo,
            title: "Clean Keyboard",
            summary: "Blocks keys, scrolling and swipes so you can wipe the keyboard and trackpad without typing or clicking anything.",
            steps: [
                "Click Clean Keyboard in the octopus panel.",
                "Wipe away: the screen dims and every key is ignored.",
                "Hold the on-screen button for a second to unlock. It also unlocks by itself after 5 minutes.",
            ],
            primary: ("Lock Keyboard", { if !model.lockKeyboard() { Permissions.requestAccessibility() } }),
            settings: { model.page = .cleanKeyboard }
        ) { EmptyView() }
    }

    private var copyTextCard: some View {
        let shortcut = model.config.copyTextHotkey
        return GuideToolCard(
            symbol: "text.viewfinder",
            tint: .teal,
            title: "Copy Text",
            summary: "Copies the text from anything on screen: photos, PDFs, paused videos, screen shares, error messages.",
            steps: [
                shortcut.isSet ? "Press \(shortcut.display), or click Copy Text in the octopus panel." : "Click Copy Text in the octopus panel.",
                "Drag a box over the text you want.",
                "Paste it anywhere. A box around a QR code copies its link.",
            ],
            primary: ("Try It", { TextGrabber.shared.start() }),
            settings: { model.page = .copyText }
        ) { EmptyView() }
    }

    // MARK: Tips

    private var tips: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Good to know").font(.title2.bold())
            Card(spacing: 14) {
                tip("hand.raised", "Typing with a palm on the trackpad?",
                    "Gestures ignore taps right after you type, fingers too far apart, and touches near the edges. Adjust it under Gestures → Tuning.")
                Divider()
                tip("pause.circle", "Pausing gestures",
                    "Click Gestures in the octopus panel to pause them all. The octopus fades while they're paused.")
                Divider()
                tip("exclamationmark.triangle", "Other gesture apps",
                    "If BetterTouchTool or similar runs at the same time, both react to a gesture. Octo warns you when it sees one.")
                Divider()
                tip("lock.shield", "Privacy",
                    "Everything runs on your Mac. Copy Text only looks at the box you draw, and only when you start it.")
            }
        }
    }

    private func tip(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One numbered step in "Getting started".
private struct StartStep<Accessory: View>: View {
    let number: Int
    let title: String
    let caption: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor))
            Text(title).font(.headline)
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            accessory
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// A tool explained: icon, what it does, an optional picture, three steps, and buttons.
private struct GuideToolCard<Extra: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let summary: String
    let steps: [String]
    let primary: (title: String, action: () -> Void)
    let settings: () -> Void
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint)
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)
                Text(title).font(.title3.bold())
            }
            Text(summary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            extra

            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(tint)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(tint.opacity(0.15)))
                        Text(step)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(primary.title, action: primary.action)
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                Button("Settings", action: settings)
                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.13), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
        )
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.25)))
    }
}
