import AppKit
import Observation
import ServiceManagement
import OctoCore

/// One sidebar tab per tool, plus General and About. To add a tool (like Clipboard), add a case
/// here, put it in `groups`, give it a page in `SettingsRoot`, and a tile in `MenuPanel`.
enum SettingsPage: String, CaseIterable, Identifiable {
    case guide, gestures, keepAwake, cleanKeyboard, copyText, general, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .guide: "Guide"
        case .gestures: "Gestures"
        case .keepAwake: "Keep Awake"
        case .cleanKeyboard: "Clean Keyboard"
        case .copyText: "Copy Text"
        case .general: "General"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .guide: "book"
        case .gestures: "hand.tap"
        case .keepAwake: "cup.and.saucer"
        case .cleanKeyboard: "keyboard"
        case .copyText: "text.viewfinder"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }

    static let groups: [(title: String?, pages: [SettingsPage])] = [
        (nil, [.guide]),
        ("Tools", [.gestures, .keepAwake, .cleanKeyboard, .copyText]),
        (nil, [.general, .about]),
    ]
}

/// The tabs inside the Gestures page.
enum GestureTab: String, CaseIterable, Identifiable {
    case list, apps, tuning, test

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "Gestures"
        case .apps: "Apps"
        case .tuning: "Tuning"
        case .test: "Test"
        }
    }
}

/// State shared by the settings window and the menu bar item. Only touched on the main thread.
@Observable
final class AppModel {
    static let shared = AppModel()

    @ObservationIgnored var persists = true

    var config: Config {
        didSet {
            guard config != oldValue else { return }
            Engine.shared.update(config: config)
            if keepAwake {
                KeepAwake.shared.set(true, screenOn: config.awakeKeepsScreenOn)
            }
            scheduleSave()
            onChange?()
        }
    }

    /// Keep awake is on. Not saved: it starts off each time Octo starts.
    private(set) var keepAwake = false
    /// Lets the menu bar icons follow changes.
    @ObservationIgnored var onChange: (() -> Void)?

    /// The keyboard is blocked for cleaning.
    var keyboardLocked = false
    /// The Copy Text shortcut is already used by another app.
    var hotkeyTaken = false
    /// Copy Text may capture the screen.
    var screenRecordingGranted = false
    /// Which tab of the Gestures page is showing.
    var gestureTab: GestureTab = .list
    /// The gesture editor is open: other parts of Octo don't switch pages or tabs meanwhile.
    var editingGesture = false

    func refreshScreenRecording() {
        screenRecordingGranted = TextGrabber.hasPermission
    }

    /// Blocks the keyboard for cleaning. Returns false if macOS doesn't allow it.
    func lockKeyboard() -> Bool {
        KeyboardLock.shared.lock()
    }

    func setKeepAwake(_ on: Bool) {
        keepAwake = KeepAwake.shared.set(on, screenOn: config.awakeKeepsScreenOn)
        Log.write("Keep awake \(keepAwake ? "on" : "off")")
        onChange?()
    }

    var page: SettingsPage = .gestures
    var log: [LogEntry] = []
    var liveTouches: [LiveTouch] = []
    var liveTrackpad: TrackpadInfo?
    var livePressed = false
    var trackpads: [TrackpadInfo] = []
    var accessibilityGranted = false
    var clickGuardRunning = false
    var launchAtLogin = false
    var launchAtLoginNote: String?

    @ObservationIgnored var liveViewers = 0 {
        didSet { Engine.shared.setLiveActive(liveViewers > 0) }
    }
    @ObservationIgnored private var saveItem: DispatchWorkItem?

    init() {
        config = Self.loadConfig()
        refreshLaunchAtLogin()
    }

    // MARK: Saving

    static var configURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Octo", isDirectory: true).appendingPathComponent("config.json")
    }

    static func loadConfig() -> Config {
        guard let data = try? Data(contentsOf: configURL) else { return Config() }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            // Not readable at all (say, a typo while editing it by hand): keep a copy before the
            // defaults are saved over it.
            let copy = configURL.deletingLastPathComponent().appendingPathComponent("config.broken.json")
            try? FileManager.default.removeItem(at: copy)
            try? FileManager.default.copyItem(at: configURL, to: copy)
            Log.write("Settings file couldn't be read, so Octo started with the defaults. The old file is kept as config.broken.json.")
            return Config()
        }
    }

    private func scheduleSave() {
        guard persists else { return }
        saveItem?.cancel()
        let snapshot = config
        let item = DispatchWorkItem {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: Self.configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: Self.configURL, options: .atomic)
        }
        saveItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    /// Writes a change that's still waiting to be saved (when Octo quits).
    func saveNow() {
        guard let item = saveItem, !item.isCancelled else { return }
        item.perform()
        item.cancel()
        saveItem = nil
    }

    // MARK: Gesture list

    var sortedBindings: [GestureBinding] {
        config.bindings.enumerated()
            .sorted { ($0.element.gesture.sortIndex, $0.offset) < ($1.element.gesture.sortIndex, $1.offset) }
            .map(\.element)
    }

    func upsert(_ binding: GestureBinding) {
        if let i = config.bindings.firstIndex(where: { $0.id == binding.id }) {
            config.bindings[i] = binding
        } else {
            config.bindings.append(binding)
        }
    }

    func delete(_ id: UUID) {
        config.bindings.removeAll { $0.id == id }
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard let i = config.bindings.firstIndex(where: { $0.id == id }) else { return }
        config.bindings[i].enabled = enabled
    }

    // MARK: Browsers

    var installedBrowsers: [AppRef] {
        KnownApps.browsers.filter { AppLocator.isInstalled($0.bundleID) }
    }

    var browserNames: String {
        let names = (installedBrowsers + config.extraBrowsers)
            .filter { config.isBrowser($0.bundleID) }
            .map(\.name)
        return names.isEmpty ? "No browsers selected" : names.joined(separator: ", ")
    }

    func setBrowser(_ bundleID: String, included: Bool) {
        if KnownApps.browsers.contains(where: { $0.bundleID == bundleID }) {
            config.excludedBrowsers.removeAll { $0 == bundleID }
            if !included { config.excludedBrowsers.append(bundleID) }
        } else if !included {
            config.extraBrowsers.removeAll { $0.bundleID == bundleID }
        }
    }

    func addBrowsers(_ apps: [AppRef]) {
        for app in apps {
            if KnownApps.browsers.contains(where: { $0.bundleID == app.bundleID }) {
                config.excludedBrowsers.removeAll { $0 == app.bundleID }
            } else if !config.extraBrowsers.contains(where: { $0.bundleID == app.bundleID }) {
                config.extraBrowsers.append(app)
            }
        }
    }

    // MARK: Other gesture apps

    /// Apps that also turn trackpad gestures into actions. If one runs alongside Octo,
    /// a gesture can fire twice (two tabs open, the tab moves twice).
    static let gestureApps: [AppRef] = [
        AppRef(bundleID: "com.hegenberg.BetterTouchTool", name: "BetterTouchTool"),
        AppRef(bundleID: "art.ginzburg.MiddleClick", name: "MiddleClick"),
        AppRef(bundleID: "com.jitouch.Jitouch", name: "Jitouch"),
    ]

    var conflicts: [AppRef] = []

    func refreshConflicts() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let found = Self.gestureApps.filter { running.contains($0.bundleID) }
        guard found != conflicts else { return }
        conflicts = found
        if !found.isEmpty { Log.write("Also running: \(found.map(\.name).joined(separator: ", "))") }
    }

    func quitConflicts() {
        for app in conflicts {
            NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).forEach { $0.terminate() }
        }
    }

    // MARK: Log and live view

    func addLog(_ entry: LogEntry) {
        log.insert(entry, at: 0)
        if log.count > 50 { log.removeLast(log.count - 50) }
    }

    // MARK: Launch at login

    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        launchAtLoginNote = status == .requiresApproval
            ? "Approve Octo in System Settings → General → Login Items."
            : nil
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLogin()
        } catch {
            refreshLaunchAtLogin()
            launchAtLoginNote = "Couldn't change this: \(error.localizedDescription)"
        }
    }
}
