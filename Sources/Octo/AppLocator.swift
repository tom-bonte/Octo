import AppKit
import ApplicationServices
import OctoCore
import UniformTypeIdentifiers

enum AppLocator {
    struct App {
        let bundleID: String?
        let name: String
    }

    /// The app owning the normal window under a screen point (top-left origin, like CGEvent).
    static func app(at point: CGPoint) -> App? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in windows {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(point),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let running = NSRunningApplication(processIdentifier: pid) else { continue }
            return App(bundleID: running.bundleIdentifier, name: running.localizedName ?? "this app")
        }
        return nil
    }

    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func isInstalled(_ bundleID: String) -> Bool { url(for: bundleID) != nil }

    static func icon(for bundleID: String) -> NSImage? {
        guard let url = url(for: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

}

enum Permissions {
    static func isTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// The "Allow" buttons. The first time, macOS's own prompt adds Octo to the Accessibility list
    /// (it has a button to System Settings). After that, open the list directly.
    static func requestAccessibility() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "askedForAccessibility") {
            defaults.set(true, forKey: "askedForAccessibility")
            if !isTrusted(prompt: true) { return }
        }
        openAccessibilitySettings()
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
