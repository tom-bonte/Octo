import AppKit
import SwiftUI
import OctoCore

/// `Octo --snapshot <folder>` renders each settings page (light and dark) to PNG,
/// with sample data, so the UI can be checked without clicking through it.
enum Snapshotter {
    static func run(into directory: String, model: AppModel) {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        useSampleData(model)

        let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
        for (suffix, appearance) in appearances {
            for page in SettingsPage.allCases {
                model.page = page
                if page == .gestures {
                    for tab in GestureTab.allCases {
                        model.gestureTab = tab
                        let height: CGFloat = tab == .list || tab == .apps ? 760 : 1300
                        render(SettingsRoot().environment(model), size: CGSize(width: 900, height: height), appearance: appearance,
                               to: folder.appendingPathComponent("gestures-\(tab.rawValue)-\(suffix).png"))
                    }
                    model.gestureTab = .list
                    continue
                }
                render(SettingsRoot().environment(model), size: CGSize(width: 900, height: page == .guide ? 2050 : 760), appearance: appearance,
                       to: folder.appendingPathComponent("\(page.rawValue)-\(suffix).png"))
            }
            let reload = model.config.bindings.first { $0.action == .hardReload } ?? model.config.bindings[0]
            render(BindingEditor(binding: reload, isNew: false).environment(model), size: CGSize(width: 620, height: 600),
                   appearance: appearance, to: folder.appendingPathComponent("editor-\(suffix).png"))
        }
        render(AppChooser(title: "Add apps for this gesture", alreadyAdded: ["com.apple.Safari"]) { _ in },
               size: CGSize(width: 440, height: 540), appearance: .aqua,
               to: folder.appendingPathComponent("chooser-light.png"))
        model.accessibilityGranted = true
        model.page = .gestures
        render(SettingsRoot().environment(model), size: CGSize(width: 900, height: 700), appearance: .aqua,
               to: folder.appendingPathComponent("gestures-granted-light.png"))
        model.conflicts = []
        for (suffix, appearance) in appearances {
            render(MenuPanel(openSettings: { _ in }, cleanKeyboard: {}, copyText: {}, quit: {}).environment(model),
                   size: CGSize(width: 340, height: 360), appearance: appearance,
                   to: folder.appendingPathComponent("menu-panel-\(suffix).png"))
        }
        render(KeyboardLockView(unlocksAt: Date().addingTimeInterval(299)) {}, size: CGSize(width: 1100, height: 720),
               appearance: .darkAqua, to: folder.appendingPathComponent("keyboard-lock.png"))
        for (name, gesturesOn, awake) in [("normal", true, false), ("awake", true, true), ("paused", false, false)] {
            writeIcon(StatusIcon.image(gesturesOn: gesturesOn, awake: awake),
                      to: folder.appendingPathComponent("menubar-icon-\(name).png"))
        }
        print("Snapshots written to \(folder.path)")
    }

    /// Example settings, trackpad, fingers and log, for pictures of the app.
    static func useSampleData(_ model: AppModel) {
        model.config = Config()
        AppInfo.supportURL = URL(string: "https://ko-fi.com/example")
        AppInfo.websiteURL = URL(string: "https://github.com/example/octo")
        model.accessibilityGranted = false
        model.conflicts = [AppModel.gestureApps[0]]
        model.trackpads = [TrackpadInfo(id: 0, familyID: 109, builtIn: true, widthMM: 124.8, heightMM: 76.8)]
        model.liveTrackpad = model.trackpads.first
        model.liveTouches = [
            LiveTouch(id: 9, x: 9, y: 30, role: .ignored),
            LiveTouch(id: 1, x: 58, y: 36, role: .resting),
            LiveTouch(id: 2, x: 79, y: 39, role: .tapping),
        ]
        model.log = [
            LogEntry(kind: .action, title: "1 resting finger, tap right", detail: "Next tab in Google Chrome"),
            LogEntry(kind: .blocked, title: "Extra click blocked", detail: "Tap to click added a click to a gesture tap"),
            LogEntry(kind: .action, title: "3-finger click", detail: "Open link in new tab in Safari"),
            LogEntry(kind: .noAction, title: "1 resting finger, tap left", detail: "Nothing set for Xcode"),
        ]
    }

    /// The menu bar icon, enlarged on white so it can be checked.
    private static func writeIcon(_ image: NSImage, to url: URL) {
        let scale: CGFloat = 6
        let size = NSSize(width: image.size.width * scale + 24, height: image.size.height * scale + 24)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.draw(in: NSRect(x: 12, y: 12, width: image.size.width * scale, height: image.size.height * scale))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func render<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name, to url: URL) {
        // Offscreen captures skip the window's own background, so paint it in.
        let host = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -30000, y: -30000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = host
        window.orderFrontRegardless()
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        window.orderOut(nil)
    }
}
