import AppKit
import SwiftUI
import OctoCore

/// What opens when you click Octo in the menu bar: one-click tiles for each tool.
/// To add a tool later (like Clipboard), add a `ToolTile` here and a page under Tools in Settings.
struct MenuPanel: View {
    @Environment(AppModel.self) private var model
    let openSettings: (SettingsPage) -> Void
    let cleanKeyboard: () -> Void
    let copyText: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !model.accessibilityGranted {
                notice("Octo needs Accessibility permission to work.", button: "Allow…") {
                    Permissions.requestAccessibility()
                }
            }
            if let other = model.conflicts.first {
                notice("\(other.name) is also running, so gestures may fire twice.", button: "Quit It") {
                    model.quitConflicts()
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ToolTile(
                    title: "Keep Awake",
                    symbol: model.keepAwake ? "cup.and.saucer.fill" : "cup.and.saucer",
                    state: model.keepAwake ? "On" : "Off",
                    isOn: model.keepAwake,
                    tint: .orange
                ) {
                    model.setKeepAwake(!model.keepAwake)
                }
                ToolTile(
                    title: "Clean Keyboard",
                    symbol: "keyboard",
                    state: model.keyboardLocked ? "Locked" : "Click to lock",
                    isOn: model.keyboardLocked,
                    tint: .indigo,
                    action: cleanKeyboard
                )
                ToolTile(
                    title: "Copy Text",
                    symbol: "text.viewfinder",
                    state: model.config.copyTextHotkey.isSet ? model.config.copyTextHotkey.display : "Click to start",
                    isOn: false,
                    tint: .teal,
                    action: copyText
                )
                ToolTile(
                    title: "Gestures",
                    symbol: "hand.tap",
                    state: model.config.enabled ? "On" : "Paused",
                    isOn: model.config.enabled,
                    tint: .blue
                ) {
                    model.config.enabled.toggle()
                }
            }

            Divider()

            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    FooterButton(title: "Test & Tune", symbol: "slider.horizontal.3") {
                        if !model.editingGesture { model.gestureTab = .test }
                        openSettings(.gestures)
                    }
                    .help("Try gestures and adjust how they feel")
                    Spacer(minLength: 8)
                    FooterButton(title: "Settings…", symbol: "gearshape") { openSettings(.gestures) }
                        .keyboardShortcut(",", modifiers: .command)
                    FooterButton(title: nil, symbol: "power", action: quit)
                        .help("Quit Octo")
                }
                if AppInfo.supportURL != nil {
                    CoffeeButton()
                }
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("Octo").font(.headline)
                Text(statusLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                openSettings(.guide)
            } label: {
                Label("Guide", systemImage: "book")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .help("How Octo and its tools work")
        }
    }

    private var statusLine: String {
        if !model.accessibilityGranted { return "Needs Accessibility permission" }
        if model.keyboardLocked { return "Keyboard locked for cleaning" }
        if model.keepAwake && model.config.enabled { return "Gestures on · keeping your Mac awake" }
        if model.keepAwake { return "Keeping your Mac awake · gestures paused" }
        if !model.config.enabled { return "Gestures paused" }
        return "Gestures on"
    }

    private func notice(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(button, action: action).controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}

/// "☕ Buy me a coffee": opens the Ko-fi page (the panel closes by itself as the browser opens).
private struct CoffeeButton: View {
    @State private var hovering = false

    var body: some View {
        Button {
            AppInfo.open(AppInfo.supportURL)
        } label: {
            Text("☕  Buy me a coffee")
                .font(.callout.weight(.medium))
                .foregroundStyle(SupportCard.tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(SupportCard.tint.opacity(hovering ? 0.20 : 0.11)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Octo is free. If it saves you time, you can buy me a coffee on Ko-fi.")
        .frame(maxWidth: .infinity)
    }
}

/// A quiet text-and-icon button for the panel's bottom row, highlighted on hover.
private struct FooterButton: View {
    let title: String?
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                if let title { Text(title) }
            }
            .font(.callout)
            .foregroundStyle(hovering ? Color.primary : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title ?? "Quit Octo")
    }
}

/// A big one-click toggle, like the tiles in Control Center.
struct ToolTile: View {
    let title: String
    let symbol: String
    let state: String
    let isOn: Bool
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Circle().fill(isOn ? Color.white.opacity(0.25) : tint.opacity(0.16))
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isOn ? Color.white : tint)
                }
                .frame(width: 34, height: 34)
                Spacer(minLength: 4)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(state)
                    .font(.system(size: 11))
                    .foregroundStyle(isOn ? Color.white.opacity(0.85) : Color.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? tint : Color.primary.opacity(hovering ? 0.11 : 0.06))
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityValue(state)
    }
}
