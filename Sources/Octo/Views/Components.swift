import SwiftUI
import OctoCore

/// A scrolling settings page with a big title.
struct Page<Accessory: View, Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        if !title.isEmpty {
                            Text(title).font(.system(size: 26, weight: .bold))
                        }
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    accessory
                }
                .padding(.bottom, 4)
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 28)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension Page where Accessory == EmptyView {
    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
    }
}

/// Title and explanation on the left, a control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let caption {
                    Text(caption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control
        }
    }
}

struct Chip: View {
    let text: String
    var warning = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(warning ? Color.orange : Color.primary.opacity(0.75))
            .background(Capsule().fill((warning ? Color.orange : Color.secondary).opacity(0.14)))
    }
}

struct ScopeChips: View {
    let scope: AppScope

    var body: some View {
        HStack(spacing: 5) {
            if scope.isEmpty {
                Chip(text: "No apps chosen", warning: true)
            } else {
                ForEach(scope.labels, id: \.self) { Chip(text: $0) }
            }
        }
    }
}

struct AppIconView: View {
    let bundleID: String
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let icon = AppLocator.icon(for: bundleID) {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
    }
}

struct PermissionBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 22))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Octo needs Accessibility permission").font(.headline)
                Text("Without it, gestures are recognized but can't switch tabs or open links. In System Settings, go to Privacy & Security → Accessibility and turn on Octo.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Allow Access…") { Permissions.requestAccessibility() }
                .controlSize(.large)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.35)))
    }
}

/// "Enjoying Octo?" with a button to the Ko-fi page. Only shown when a support link is set.
struct SupportCard: View {
    static let tint = Color(red: 1.0, green: 0.37, blue: 0.40)

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle().fill(Self.tint.opacity(0.15))
                Image(systemName: "heart.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Self.tint)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("Enjoying Octo?").font(.headline)
                Text("Octo is free, with no ads and no tracking. If it saves you time, you can buy me a coffee.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            SupportButton()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Self.tint.opacity(0.10), Self.tint.opacity(0.03)], startPoint: .leading, endPoint: .trailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Self.tint.opacity(0.25)))
    }
}

struct SupportButton: View {
    var body: some View {
        Button {
            AppInfo.open(AppInfo.supportURL)
        } label: {
            Label("Support on Ko-fi", systemImage: "heart.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(SupportCard.tint)
        .controlSize(.large)
        .help(AppInfo.supportURL?.absoluteString ?? "")
    }
}

/// Shown while another gesture app (like BetterTouchTool) is running.
struct ConflictBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let app = model.conflicts.first {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(app.name) is also running").font(.headline)
                    Text("If it has trackpad gestures too, both apps react to the same gesture: two tabs open, or the tab moves twice. Quit it, or turn off its trackpad gestures.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Quit \(app.name)") { model.quitConflicts() }
                    .controlSize(.large)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.35)))
        }
    }
}

extension LogEntry {
    var symbol: String {
        switch kind {
        case .action: "checkmark.circle.fill"
        case .noAction: "circle.dashed"
        case .blocked: "hand.raised.fill"
        case .test: "hand.tap.fill"
        }
    }

    var color: Color {
        switch kind {
        case .action: .green
        case .noAction: .secondary
        case .blocked: .orange
        case .test: .accentColor
        }
    }
}
