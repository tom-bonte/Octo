import AppKit
import SwiftUI

/// Version, what Octo promises (free, private, open source), support and links.
struct AboutPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 112, height: 112)
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                    Text("Octo").font(.system(size: 30, weight: .bold))
                    Text("Version \(AppInfo.version) (\(AppInfo.build))")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Small tools for your Mac, in one menu bar app.")
                        .font(.title3)
                        .padding(.top, 2)
                }
                .padding(.top, 12)

                if AppInfo.websiteURL != nil {
                    HStack(spacing: 10) {
                        Button("GitHub Page") { AppInfo.open(AppInfo.websiteURL) }
                        Button("What's New") { AppInfo.open(AppInfo.releasesURL) }
                        Button("Report a Problem") { AppInfo.open(AppInfo.issuesURL) }
                    }
                }

                Card(spacing: 14) {
                    promise("lock.shield", "Private",
                            "Everything stays on your Mac. No account, no ads, no analytics, and Octo never connects to the internet.")
                    Divider()
                    promise("gift", "Free and open source",
                            "Free to use and share under the MIT License. Anyone can read the code.")
                    Divider()
                    promise("hand.tap", "Thanks to Jitouch",
                            "Octo's gestures are inspired by Jitouch, which made the trackpad fun for years.")
                }

                if AppInfo.supportURL != nil {
                    SupportCard()
                }

                Text(AppInfo.copyright)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    private func promise(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
