import AppKit
import ScreenCaptureKit
import SwiftUI
import OctoCore

/// Pictures of Octo's real windows, with example settings, for the README:
/// `panel.png` (dark: the panel's see-through background looks muddy in light mode when it's
/// captured on its own), `settings-light.png` and `settings-dark.png`.
///
///     open -n -a /Applications/Octo.app --args --screenshots <folder>
///
/// Needs Screen Recording permission (the one Copy Text uses). Start it with `open` as above, so
/// macOS checks Octo's own permission rather than the Terminal's. The windows show for a few
/// seconds while they're captured; your own settings aren't touched.
@MainActor
enum ScreenshotMaker {
    static func run(into directory: String, model: AppModel) async {
        guard CGPreflightScreenCaptureAccess() else {
            Log.write("Screenshots: Octo needs Screen Recording permission")
            return
        }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        Snapshotter.useSampleData(model)
        model.accessibilityGranted = true
        model.conflicts = []
        model.page = .gestures
        model.gestureTab = .list

        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsRoot().environment(model)))
        window.title = "Octo"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 900, height: 600))
        window.center()

        // The panel as people see it: a real popover under a (temporary) menu bar icon.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = StatusIcon.image(gesturesOn: true, awake: false)
        let host = NSHostingController(rootView: MenuPanel(openSettings: { _ in }, cleanKeyboard: {}, copyText: {}, quit: {})
            .environment(model))
        host.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.contentViewController = host

        for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = NSAppearance(named: appearanceName)
            NSApp.appearance = appearance
            window.appearance = appearance
            popover.appearance = appearance
            host.view.appearance = appearance

            window.orderFrontRegardless()
            window.makeKey()
            NSApp.activate()
            await pause(1.0)
            await capture(window, to: folder.appendingPathComponent("settings-\(name).png"))
            window.orderOut(nil)

            if name == "dark", let button = item.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                await pause(1.0)
                if let panel = host.view.window {
                    await capture(panel, to: folder.appendingPathComponent("panel.png"))
                }
                popover.performClose(nil)
                await pause(0.4)
            }
        }
        NSStatusBar.system.removeStatusItem(item)
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Captures one window on its own (nothing behind it), with its shadow, at full resolution.
    private static func capture(_ window: NSWindow, to url: URL) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                Log.write("Screenshot \(url.lastPathComponent): window not found")
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: target)
            let config = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            config.width = Int(filter.contentRect.width * scale)
            config.height = Int(filter.contentRect.height * scale)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = false
            config.shouldBeOpaque = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            try data?.write(to: url)
            Log.write("Screenshot: \(url.path)")
        } catch {
            Log.write("Screenshot \(url.lastPathComponent) failed: \(error.localizedDescription)")
        }
    }
}
