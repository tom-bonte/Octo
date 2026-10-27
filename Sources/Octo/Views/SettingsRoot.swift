import SwiftUI
import OctoCore

struct SettingsRoot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.page }, set: { if let page = $0 { model.page = page } })) {
                ForEach(SettingsPage.groups.indices, id: \.self) { index in
                    let group = SettingsPage.groups[index]
                    Section {
                        ForEach(group.pages) { page in
                            Label(page.title, systemImage: page.symbol).tag(page)
                        }
                    } header: {
                        if let title = group.title { Text(title) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) { SidebarStatus() }
        } detail: {
            Group {
                switch model.page {
                case .guide: GuidePage()
                case .gestures: GesturesToolPage()
                case .keepAwake: KeepAwakePage()
                case .cleanKeyboard: CleanKeyboardPage()
                case .copyText: CopyTextPage()
                case .general: GeneralPage()
                case .about: AboutPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 780, minHeight: 540)
    }
}

private struct SidebarStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let (text, color): (String, Color) = {
            if !model.accessibilityGranted { return ("Needs permission", .orange) }
            if !model.config.enabled { return ("Paused", .secondary) }
            if model.trackpads.isEmpty { return ("No trackpad found", .orange) }
            return ("On", .green)
        }()
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}
