import AppKit
import SwiftUI
import OctoCore

struct BindingEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GestureBinding
    let isNew: Bool

    init(binding: GestureBinding, isNew: Bool) {
        _draft = State(initialValue: binding)
        self.isNew = isNew
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(isNew ? "Add a Gesture" : "Edit Gesture")
                        .font(.title2.bold())

                    section("Gesture") {
                        GesturePicker(selection: $draft.gesture, editingID: draft.id, currentAction: draft.action)
                        Text(draft.gesture.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    section("Action") {
                        ActionPicker(action: $draft.action)
                        Text(draft.action.behaviorNote)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    section("Works in") {
                        ScopeEditor(scope: $draft.scope)
                    }

                    let overlaps = model.config.overlaps(with: draft)
                    if draft.enabled && !overlaps.isEmpty {
                        Label {
                            Text("This gesture is also set to \(overlaps.map { "“\($0.action.title)” (\($0.scope.labels.joined(separator: ", ")))" }.joined(separator: " and ")). Where both apply, the more specific one wins; if they're equally specific, the one added first wins.")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                        .font(.callout)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        model.delete(draft.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Gesture" : "Save") {
                    model.upsert(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(draft.scope.isEmpty || !draft.action.isValid)
            }
            .padding(16)
        }
        .frame(width: 620, height: 600)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - Gesture

private struct GesturePicker: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: GestureKind
    let editingID: UUID
    /// The action being set in this editor, shown on the selected tile.
    let currentAction: ActionKind

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
            ForEach(GestureKind.catalog, id: \.self) { gesture in
                let selected = gesture == selection
                let others = model.config.summary(for: gesture, excluding: editingID, detailed: false)
                let usage = selected ? [currentAction.title, others].compactMap { $0 }.joined(separator: ", ") : others
                VStack(spacing: 4) {
                    GestureDiagram(gesture: gesture, animated: selected)
                        .frame(height: 52)
                    Text(gesture.shortTitle)
                        .font(.caption.weight(selected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(usage ?? "Free")
                        .font(.caption2.weight(usage == nil ? .regular : .medium))
                        .foregroundStyle(usage == nil ? Color.secondary : Color.accentColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1)
                )
                .contentShape(Rectangle())
                .onTapGesture { selection = gesture }
                .help(usage.map { "\(gesture.title): \(model.config.summary(for: gesture, excluding: editingID) ?? $0)" } ?? "\(gesture.title): not used yet")
            }
        }
    }
}

// MARK: - Action

private struct ActionPicker: View {
    @Binding var action: ActionKind

    var body: some View {
        HStack(spacing: 12) {
            Picker("Action", selection: Binding(
                get: { action.id },
                set: { id in
                    if id == "shortcut" {
                        if case .shortcut = action { return }
                        action = .shortcut(.unset)
                    } else if let preset = ActionKind.preset(id: id) {
                        action = preset
                    }
                }
            )) {
                ForEach(ActionKind.groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.actions, id: \.id) { item in
                            Label(item.id == "shortcut" ? "Keyboard shortcut…" : item.title, systemImage: item.symbol)
                                .tag(item.id)
                        }
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            if case let .shortcut(combo) = action {
                ShortcutRecorder(combo: Binding(get: { combo }, set: { action = .shortcut($0) }))
            }
        }
    }
}

/// Click, then press a shortcut. Esc cancels; clicking elsewhere stops recording.
///
/// For a gesture's action any key works (Octo sends it). For a system-wide shortcut
/// (`global: true`, like Copy Text's) it must include ⌘, ⌃ or ⌥ (or be an F-key), and the
/// everyday ones like ⌘Q or ⌘C are refused, because Octo would take them away from every app.
/// There, ⌫ removes the shortcut.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo
    var autoStart = true
    var global = false
    @State private var recording = false
    @State private var rejected = false
    @State private var monitor: Any?
    @State private var resignObserver: NSObjectProtocol?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(label)
                .font(.system(.body, design: .rounded).weight(.medium))
                .frame(minWidth: 150)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : .secondary)
        .help(global ? "Use ⌘, ⌃ or ⌥ with a key, or an F-key. ⌫ removes the shortcut, Esc cancels." : "Press the keys to send. Esc cancels.")
        .onAppear { if autoStart && !combo.isSet { start() } }
        .onDisappear(perform: stop)
    }

    private var label: String {
        if recording { return rejected ? "Add ⌘, ⌃ or ⌥…" : "Type a shortcut…" }
        return combo.isSet ? combo.display : "Click to record"
    }

    private func start() {
        stop()
        recording = true
        rejected = false
        let window = NSApp.keyWindow
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Keys typed in another window (a sheet, the menu bar panel) aren't for us.
            guard event.window === window else {
                stop()
                return event
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            switch (event.keyCode, modifiers.isEmpty) {
            case (53, true): // Esc cancels
                stop()
                return nil
            case (36, true), (76, true): // Return ends recording and still presses the default button
                stop()
                return event
            case (51, true) where global, (117, true) where global: // ⌫ removes a system-wide shortcut
                combo = .unset
                stop()
                return nil
            default:
                break
            }
            let recorded = KeyCombo.recorded(from: event)
            if global && !recorded.isUsableGlobally {
                rejected = true
                NSSound.beep()
                return nil
            }
            combo = recorded
            stop()
            return nil
        }
        // Clicking into another window or app stops recording.
        if let window {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { _ in stop() }
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        recording = false
        rejected = false
    }

}

extension KeyCombo {
    static func recorded(from event: NSEvent) -> KeyCombo {
        var modifiers: KeyModifiers = []
        let flags = event.modifierFlags
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return KeyCombo(keyCode: event.keyCode, key: keyName(for: event), modifiers: modifiers)
    }

    private static func keyName(for event: NSEvent) -> String {
        let special: [UInt16: String] = [
            48: "⇥", 36: "↩", 76: "⌤", 49: "Space", 51: "⌫", 117: "⌦", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let name = special[event.keyCode] { return name }
        let chars = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? "?"
        return chars.uppercased()
    }
}

// MARK: - Apps

private struct ScopeEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var scope: AppScope
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $scope.browsers) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browsers")
                    Text(model.browserNames).font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle("Finder", isOn: $scope.finder)
            Toggle(isOn: $scope.allApps) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All apps")
                    Text("Any app without a more specific setting for this gesture.").font(.caption).foregroundStyle(.secondary)
                }
            }

            ForEach(scope.apps) { app in
                HStack(spacing: 10) {
                    AppIconView(bundleID: app.bundleID, size: 20)
                    Text(app.name)
                    Spacer()
                    Button {
                        scope.apps.removeAll { $0.bundleID == app.bundleID }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove \(app.name)")
                }
                .padding(.leading, 22)
            }

            Button {
                choosing = true
            } label: {
                Label("Add a Specific App…", systemImage: "plus")
            }
            .buttonStyle(.link)
            .padding(.top, 2)

            if scope.isEmpty {
                Text("Choose at least one place for this gesture to work.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .toggleStyle(.checkbox)
        .sheet(isPresented: $choosing) {
            AppChooser(title: "Add apps for this gesture", alreadyAdded: Set(scope.apps.map(\.bundleID))) { picked in
                scope.apps += picked.filter { new in !scope.apps.contains { $0.bundleID == new.bundleID } }
            }
        }
    }
}
