import SwiftUI
import OctoCore

struct AppsPage: View {
    @Environment(AppModel.self) private var model
    @State private var installed: [AppRef] = []
    @State private var choosing = false

    var body: some View {
        let rows = installed + model.config.extraBrowsers.filter { extra in !installed.contains { $0.bundleID == extra.bundleID } }

        Page(title: "", subtitle: "Choose which apps count as browsers. Gestures set to “Browsers” work in all of them.") {
            Button {
                choosing = true
            } label: {
                Label("Add App…", systemImage: "plus")
            }
            .controlSize(.large)
        } content: {
            Card(padding: 0, spacing: 0) {
                if rows.isEmpty {
                    Text("No browsers found. Add one with “Add App…”.")
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, app in
                    if index > 0 { Divider().padding(.leading, 56) }
                    AppRow(app: app, isExtra: !KnownApps.browsers.contains { $0.bundleID == app.bundleID })
                }
            }

            Card {
                HStack(spacing: 12) {
                    AppIconView(bundleID: KnownApps.finder, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Finder").font(.headline)
                        Text("Finder has its own checkbox on each gesture. Tab switching works there, and a 3-finger click opens a folder in a new tab.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Label {
                Text("To use a gesture in any other app, edit the gesture and choose “Add a Specific App…” under Works in.")
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .onAppear { installed = model.installedBrowsers }
        .sheet(isPresented: $choosing) {
            AppChooser(
                title: "Add apps that count as browsers",
                alreadyAdded: Set(rows.filter { model.config.isBrowser($0.bundleID) }.map(\.bundleID))
            ) { apps in
                model.addBrowsers(apps)
            }
        }
    }
}

private struct AppRow: View {
    @Environment(AppModel.self) private var model
    let app: AppRef
    let isExtra: Bool

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(bundleID: app.bundleID, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                Text(app.bundleID).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            if isExtra {
                Button("Remove") { model.setBrowser(app.bundleID, included: false) }
                    .buttonStyle(.link)
            } else {
                Toggle("Counts as a browser", isOn: Binding(
                    get: { model.config.isBrowser(app.bundleID) },
                    set: { model.setBrowser(app.bundleID, included: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
