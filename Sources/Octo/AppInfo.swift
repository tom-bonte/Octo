import AppKit

/// Octo's version and public links, read from Info.plist.
/// Set `OctoSupportURL` (the Ko-fi page) and `OctoWebsiteURL` (the GitHub page) there before
/// publishing. While a link is empty, the buttons that use it are hidden.
enum AppInfo {
    static var version: String { info("CFBundleShortVersionString") ?? "1.0.0" }
    static var build: String { info("CFBundleVersion") ?? "1" }
    static var copyright: String { info("NSHumanReadableCopyright") ?? "" }

    /// Where people can support Octo (Ko-fi).
    static var supportURL: URL? = url("OctoSupportURL")
    /// Octo's public page (its GitHub repository).
    static var websiteURL: URL? = url("OctoWebsiteURL")
    static var issuesURL: URL? { websiteURL?.appendingPathComponent("issues") }
    static var releasesURL: URL? { websiteURL?.appendingPathComponent("releases") }

    static func open(_ url: URL?) {
        if let url { NSWorkspace.shared.open(url) }
    }

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private static func url(_ key: String) -> URL? {
        guard let text = info(key)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        return URL(string: text)
    }
}
