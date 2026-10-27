import SwiftUI
import OctoCore

struct GesturesPage: View {
    @Environment(AppModel.self) private var model
    @State private var editing: EditRequest?
    @State private var confirmReset = false

    private struct EditRequest: Identifiable {
        let binding: GestureBinding
        let isNew: Bool
        var id: UUID { binding.id }
    }

    var body: some View {
        Page(title: "", subtitle: "What each trackpad gesture does, and in which apps.") {
            Button {
                addGesture()
            } label: {
                Label("Add Gesture", systemImage: "plus")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        } content: {
            if !model.accessibilityGranted {
                PermissionBanner()
            }
            ConflictBanner()
            if !model.config.enabled {
                pausedBanner
            }

            VStack(spacing: 10) {
                ForEach(model.sortedBindings) { binding in
                    BindingRow(binding: binding) {
                        editing = EditRequest(binding: binding, isNew: false)
                    } duplicate: {
                        // A copy with the same gesture and apps would never fire, so it opens in
                        // the editor to change first, and only exists once it's saved.
                        var copy = binding
                        copy.id = UUID()
                        editing = EditRequest(binding: copy, isNew: true)
                    }
                }
            }

            Button(action: addGesture) {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill").font(.title3)
                    Text("Add a gesture")
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Label {
                Text("When two settings cover the same app, the more specific one wins: a named app beats Browsers or Finder, which beat All apps.")
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Button("Restore Default Gestures…", role: .destructive) { confirmReset = true }
                .buttonStyle(.link)
        }
        .confirmationDialog("Restore the default gestures?", isPresented: $confirmReset) {
            Button("Restore Defaults", role: .destructive) { model.config.bindings = Config.defaultBindings }
        } message: {
            Text("Your gesture list goes back to the starting gestures. Tuning and app settings stay as they are.")
        }
        .sheet(item: $editing) { request in
            BindingEditor(binding: request.binding, isNew: request.isNew)
                .environment(model)
        }
        // While the editor is open, other parts of Octo leave this page alone (no lost edits).
        .onChange(of: editing?.id) { model.editingGesture = editing != nil }
        .onDisappear { model.editingGesture = false }
    }

    private var pausedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "pause.circle.fill").font(.title2).foregroundStyle(.secondary)
            Text("Gestures are paused.").font(.headline)
            Spacer()
            Button("Turn On") { model.config.enabled = true }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.secondary.opacity(0.12)))
    }

    private func addGesture() {
        // Start from the first gesture that isn't used yet.
        let used = Set(model.config.bindings.map(\.gesture))
        let gesture = GestureKind.catalog.first { !used.contains($0) } ?? .fixTap(resting: 1, side: .right, taps: 2)
        editing = EditRequest(
            binding: GestureBinding(gesture: gesture, action: .nextTab, scope: .browsersOnly),
            isNew: true
        )
    }
}

private struct BindingRow: View {
    @Environment(AppModel.self) private var model
    let binding: GestureBinding
    let edit: () -> Void
    let duplicate: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            GestureDiagram(gesture: binding.gesture, animated: hovering)
                .frame(width: 96, height: 62)

            VStack(alignment: .leading, spacing: 6) {
                Text(binding.gesture.title).font(.headline)
                HStack(spacing: 6) {
                    Image(systemName: binding.action.symbol)
                        .foregroundStyle(.tint)
                        .frame(width: 18)
                    Text(binding.action.title)
                }
                HStack(spacing: 5) {
                    ScopeChips(scope: binding.scope)
                    if binding.enabled, let other = model.config.overlaps(with: binding).first {
                        Chip(text: "Same gesture as “\(other.action.title)”", warning: true)
                            .help("Both are set for the same apps, so only one of them can run. Change the gesture or the apps of one.")
                    }
                }
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .opacity(hovering ? 1 : 0)

            Toggle("Enabled", isOn: Binding(
                get: { binding.enabled },
                set: { model.setEnabled(binding.id, $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .help(binding.enabled ? "Turn this gesture off" : "Turn this gesture on")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(hovering ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08))
        )
        .opacity(binding.enabled ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture(perform: edit)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Edit…", action: edit)
            Button("Duplicate…", action: duplicate)
            Divider()
            Button("Delete", role: .destructive) { model.delete(binding.id) }
        }
    }
}
