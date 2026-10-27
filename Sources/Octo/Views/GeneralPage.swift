import AppKit
import SwiftUI
import OctoCore

/// App-wide settings only. Each tool's own settings live on that tool's tab.
struct GeneralPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Page(title: "General", subtitle: "Startup, permissions and your settings file.") {
            Card {
                SettingRow(title: "Open at login", caption: model.launchAtLoginNote ?? "Start Octo automatically when you log in.") {
                    Toggle("Open at login", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            Card {
                Text("Permissions").font(.headline)
                PermissionRow(
                    title: "Accessibility",
                    caption: "Lets Octo send shortcuts, handle multi-finger clicks and lock the keyboard.",
                    granted: model.accessibilityGranted,
                    buttonTitle: "Allow Access…",
                    open: Permissions.requestAccessibility
                )
                Divider()
                PermissionRow(
                    title: "Screen Recording",
                    caption: "Lets Copy Text read the part of the screen you select. Nothing is saved or sent anywhere.",
                    granted: model.screenRecordingGranted,
                    open: TextGrabber.openPermissionSettings
                )
            }

            Card {
                SettingRow(title: "Settings file", caption: "All your settings in one readable file, safe to back up.") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([AppModel.configURL])
                    }
                    .disabled(!FileManager.default.fileExists(atPath: AppModel.configURL.path))
                }
            }

        }
        .onAppear { model.refreshScreenRecording() }
    }
}

struct PermissionRow: View {
    let title: String
    let caption: String
    let granted: Bool
    var buttonTitle = "Open System Settings"
    let open: () -> Void

    var body: some View {
        SettingRow(title: title, caption: caption) {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(buttonTitle, action: open)
            }
        }
    }
}
