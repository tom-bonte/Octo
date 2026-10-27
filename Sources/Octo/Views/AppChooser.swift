import AppKit
import SwiftUI
import OctoCore

/// A searchable list of installed apps, shown as a sheet inside Octo's window.
/// (Used instead of the system file picker, which could open out of sight and block the app.)
struct AppChooser: View {
    let title: String
    /// Apps already added; shown greyed out.
    let alreadyAdded: Set<String>
    let onAdd: ([AppRef]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var apps: [AppRef] = []
    @State private var loading = true
    @State private var search = ""
    @State private var selected: Set<String> = []

    private var filtered: [AppRef] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.bold())
                TextField("Search apps", text: $search)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(16)

            Group {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    Text("No apps match “\(search)”.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered) { app in
                        row(app)
                    }
                }
            }

            Divider()
            HStack {
                Text(selected.isEmpty ? "Click apps to select them" : "\(selected.count) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(selected.count > 1 ? "Add \(selected.count) Apps" : "Add") {
                    onAdd(apps.filter { selected.contains($0.bundleID) })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 440, height: 540)
        .task {
            apps = await Task.detached { InstalledApps.load() }.value
            loading = false
        }
    }

    private func row(_ app: AppRef) -> some View {
        let added = alreadyAdded.contains(app.bundleID)
        let isSelected = selected.contains(app.bundleID)
        return HStack(spacing: 10) {
            AppIconView(bundleID: app.bundleID, size: 24)
            Text(app.name)
            Spacer()
            if added {
                Text("Added").font(.caption).foregroundStyle(.secondary)
            } else {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.6))
            }
        }
        .padding(.vertical, 2)
        .opacity(added ? 0.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !added else { return }
            if isSelected { selected.remove(app.bundleID) } else { selected.insert(app.bundleID) }
        }
    }
}

enum InstalledApps {
    /// Apps in the usual Applications folders (one level of subfolders too), sorted by name.
    static func load() -> [AppRef] {
        let fm = FileManager.default
        let folders = [
            "/Applications", "/Applications/Utilities",
            "/System/Applications", "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]
        var seen: Set<String> = [Engine.ownBundleID]
        var apps: [AppRef] = []

        func add(_ path: String) {
            guard let id = Bundle(path: path)?.bundleIdentifier, !seen.contains(id) else { return }
            seen.insert(id)
            var name = fm.displayName(atPath: path)
            if name.hasSuffix(".app") { name.removeLast(4) }
            apps.append(AppRef(bundleID: id, name: name))
        }

        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            for item in items {
                let path = folder + "/" + item
                if item.hasSuffix(".app") {
                    add(path)
                } else if !item.hasPrefix("."), folder.hasSuffix("Applications"),
                          let inner = try? fm.contentsOfDirectory(atPath: path) {
                    // App suites like "Microsoft Office" keep their apps in a subfolder.
                    for innerItem in inner where innerItem.hasSuffix(".app") {
                        add(path + "/" + innerItem)
                    }
                }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
