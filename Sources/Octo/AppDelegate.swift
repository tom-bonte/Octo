import AppKit
import SwiftUI
import OctoCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private let model = AppModel.shared
    private let snapshotDirectory: String?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?

    init(snapshotDirectory: String?) {
        self.snapshotDirectory = snapshotDirectory
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-test-copy-text") {
            CopyTextSelfTest.run()
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--self-test-keyboard-lock") {
            KeyboardLockSelfTest.run()
            NSApp.terminate(nil)
            return
        }
        if let snapshotDirectory {
            model.persists = false
            Snapshotter.run(into: snapshotDirectory, model: model)
            NSApp.terminate(nil)
            return
        }
        let arguments = CommandLine.arguments
        if let i = arguments.firstIndex(of: "--screenshots"), i + 1 < arguments.count {
            model.persists = false
            Task { @MainActor in
                await ScreenshotMaker.run(into: arguments[i + 1], model: self.model)
                NSApp.terminate(nil)
            }
            return
        }

        // One copy only.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Engine.ownBundleID)
            .filter { $0 != NSRunningApplication.current }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }

        Log.write("Octo \(AppInfo.version) started from \(Bundle.main.bundlePath)")
        if !confirmLocation() { return }
        setUpMainMenu()
        KeyLayout.shared.startObserving()

        let engine = Engine.shared
        engine.update(config: model.config)
        engine.onLog = { [model] entry in model.addLog(entry) }
        engine.onPerformed = { [model] gesture, action in
            if model.config.showGestureHints { GestureHint.show(gesture: gesture, action: action) }
        }
        engine.onLive = { [model] touches, trackpad, pressed in
            model.liveTouches = touches
            model.liveTrackpad = trackpad
            model.livePressed = pressed
        }
        trackFrontmostApp()
        watchGestureApps()

        TrackpadManager.shared.onChange = { [model] trackpads in
            model.trackpads = trackpads
            Log.write("Trackpads: \(trackpads.map { "\($0.name) \(Int($0.widthMM))×\(Int($0.heightMM)) mm" })")
        }
        TrackpadManager.shared.start()

        setUpStatusItem()
        TextGrabber.shared.keepLineBreaks = { [model] in model.config.copyTextKeepsLineBreaks }
        HotKey.shared.onPress = { TextGrabber.shared.start() }
        registerHotKey()
        model.refreshScreenRecording()
        model.onChange = { [weak self] in
            self?.updateStatusIcon()
            self?.registerHotKey()
            if let model = self?.model { FingerOverlay.shared.update(visible: model.config.showFingersOverlay, model: model) }
        }
        FingerOverlay.shared.update(visible: model.config.showFingersOverlay, model: model)
        KeyboardLock.shared.onChange = { [weak self] in
            self?.model.keyboardLocked = KeyboardLock.shared.isLocked
        }
        // Coming back from System Settings: show the current login item and permission state.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.model.refreshLaunchAtLogin()
            self?.model.refreshScreenRecording()
        }
        // No system prompt at launch: the Guide explains first, and its Allow button asks macOS.
        checkPermission(prompt: false)
        if !model.accessibilityGranted {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                self?.checkPermission(prompt: false)
            }
        }

        let defaults = UserDefaults.standard
        if !model.accessibilityGranted || !defaults.bool(forKey: "launchedBefore") {
            defaults.set(true, forKey: "launchedBefore")
            showSettings(.guide)
        }
    }

    /// Opening the app again (from Finder or Spotlight) shows the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Octo re-opening itself to come forward: the window is already on its way.
        if activatingSelf { return true }
        showSettings(nil)
        return true
    }

    // MARK: Where Octo runs from

    /// Downloaded apps opened straight from the disk image or Downloads run from a temporary copy
    /// (macOS "translocates" them), where permissions don't stick. Ask to move Octo first.
    /// Returns false when Octo quits.
    private func confirmLocation() -> Bool {
        let path = Bundle.main.bundlePath
        let readOnly = (try? Bundle.main.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true
        // Translocated, or still on the disk image (read-only). Another drive is fine.
        guard path.contains("/AppTranslocation/") || readOnly else { return true }
        Log.write("Running from a temporary location: \(path)")
        let alert = NSAlert()
        alert.messageText = "Move Octo to your Applications folder"
        alert.informativeText = "Octo is running from a temporary location, where macOS can't keep its permissions. Quit Octo, drag it into your Applications folder, and open it from there."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Open Anyway")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return true }
        NSApp.terminate(nil)
        return false
    }

    // MARK: Menu bar menus

    /// The menus macOS shows while the Settings window is open. Besides About and Quit, they make
    /// standard shortcuts work there: ⌘W closes the window, ⌘C/⌘V copy and paste in text fields.
    private func setUpMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu(title: "Octo")
        appMenu.addItem(item("About Octo", #selector(showAbout), target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(showSettingsFromMenu), key: ",", target: self))
        if AppInfo.supportURL != nil {
            appMenu.addItem(item("Support Octo…", #selector(openSupport), target: self))
        }
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide Octo", #selector(NSApplication.hide(_:)), key: "h"))
        appMenu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option]))
        appMenu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit Octo", #selector(NSApplication.terminate(_:)), key: "q"))
        main.addItem(submenu(appMenu))

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(item("Undo", Selector(("undo:")), key: "z"))
        editMenu.addItem(item("Redo", Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(item("Cut", #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(item("Copy", #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(item("Paste", #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(item("Select All", #selector(NSText.selectAll(_:)), key: "a"))
        main.addItem(submenu(editMenu))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(item("Close", #selector(NSWindow.performClose(_:)), key: "w"))
        windowMenu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        windowMenu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        main.addItem(submenu(windowMenu))
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(item("Octo Guide", #selector(showGuide), key: "?", target: self))
        if AppInfo.issuesURL != nil {
            helpMenu.addItem(item("Report a Problem…", #selector(reportProblem), target: self))
        }
        main.addItem(submenu(helpMenu))
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = main
    }

    /// A menu item. Octo's own actions go to this delegate; the standard ones (`target: nil`)
    /// go to whichever window or text field is active.
    private func item(_ title: String, _ action: Selector, key: String = "",
                      modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    private func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @objc private func showAbout() { showSettings(.about) }
    @objc private func showSettingsFromMenu() { showSettings(nil) }
    @objc private func showGuide() { showSettings(.guide) }
    @objc private func openSupport() { AppInfo.open(AppInfo.supportURL) }
    @objc private func reportProblem() { AppInfo.open(AppInfo.issuesURL) }

    // MARK: Permission

    private func checkPermission(prompt: Bool) {
        let granted = Permissions.isTrusted(prompt: prompt)
        if model.accessibilityGranted != granted || prompt {
            Log.write("Accessibility permission: \(granted ? "granted" : "not granted")")
        }
        if model.accessibilityGranted != granted {
            model.accessibilityGranted = granted
            updateStatusIcon()
        }
        if granted {
            if !ClickGuard.shared.isRunning {
                model.clickGuardRunning = ClickGuard.shared.start()
                Log.write("Click handling \(model.clickGuardRunning ? "started" : "failed to start")")
            }
            if !KeyWatcher.shared.isRunning {
                let started = KeyWatcher.shared.start()
                Log.write("Typing detection \(started ? "started" : "failed to start")")
            }
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    private func trackFrontmostApp() {
        let update: (NSRunningApplication?) -> Void = { app in
            Engine.shared.setFrontmost(bundleID: app?.bundleIdentifier, name: app?.localizedName ?? "this app")
        }
        update(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            update(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
    }

    /// Keeps track of BetterTouchTool and similar apps, which would make gestures fire twice.
    private func watchGestureApps() {
        model.refreshConflicts()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.model.refreshConflicts()
                self?.updateStatusIcon()
            }
        }
    }

    // MARK: Menu bar panel

    private lazy var panel: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: MenuPanel(
            openSettings: { [weak self] page in
                self?.panel.performClose(nil)
                self?.showSettings(page)
            },
            cleanKeyboard: { [weak self] in
                self?.panel.performClose(nil)
                // Let the panel close before the cleaning screen appears.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.toggleKeyboardLock() }
            },
            copyText: { [weak self] in
                self?.panel.performClose(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { TextGrabber.shared.start() }
            },
            quit: { NSApp.terminate(nil) }
        ).environment(model))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        return popover
    }()

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        updateStatusIcon()
    }

    /// Watches clicks while the panel is open, to close it on any click outside it.
    private var panelClickMonitors: [Any] = []
    private let panelAnchor = PanelAnchor()

    @objc private func togglePanel() {
        guard let button = statusItem?.button else { return }
        if panel.isShown {
            panel.performClose(nil)
        } else {
            let anchor = panelAnchor.view(under: button)
            panel.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
            FocusReturn.remember()
            NSApp.activate()
            panel.contentViewController?.view.window?.makeKey()
            closePanelOnOutsideClicks()
        }
    }

    /// macOS only closes a "transient" panel by itself when Octo is the active app, which a
    /// menu bar app often isn't. So watch clicks ourselves: in other apps (global monitor) and in
    /// Octo's own other windows (local monitor).
    private func closePanelOnOutsideClicks() {
        stopWatchingPanelClicks()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            self?.panel.performClose(nil)
        }) {
            panelClickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            guard let self else { return event }
            let panelWindow = self.panel.contentViewController?.view.window
            let iconWindow = self.statusItem?.button?.window // its own click toggles the panel
            if event.window !== panelWindow && event.window !== iconWindow {
                self.panel.performClose(nil)
            }
            return event
        }) {
            panelClickMonitors.append(local)
        }
    }

    private func stopWatchingPanelClicks() {
        panelClickMonitors.forEach { NSEvent.removeMonitor($0) }
        panelClickMonitors = []
    }

    func popoverDidClose(_ notification: Notification) {
        stopWatchingPanelClicks()
        panelAnchor.hide()
        // Opening Settings from the panel: stay on the Desktop with it. (The panel finishes closing
        // after Settings has started coming forward, so this must not hand focus back.)
        if settingsWindow == nil { FocusReturn.giveBack() }
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        button.image = StatusIcon.image(gesturesOn: model.config.enabled, awake: model.keepAwake)
        button.appearsDisabled = !model.accessibilityGranted
        button.toolTip = model.keepAwake ? "Octo · keeping your Mac awake" : "Octo"
    }

    private func registerHotKey() {
        // A shortcut without ⌘, ⌃ or ⌥ (say, from an edited settings file) would take a plain key
        // away from every app, so it isn't used.
        let combo = model.config.copyTextHotkey
        model.hotkeyTaken = !HotKey.shared.register(combo.isUsableGlobally ? combo : .unset)
    }

    // MARK: Clean keyboard

    func toggleKeyboardLock() {
        if KeyboardLock.shared.isLocked {
            KeyboardLock.shared.unlock(reason: "chose Unlock Keyboard")
            return
        }
        guard !model.lockKeyboard() else { return }
        let alert = NSAlert()
        alert.messageText = "Couldn't lock the keyboard"
        alert.informativeText = "Octo needs Accessibility permission to block keys. Turn on Octo in System Settings → Privacy & Security → Accessibility."
        alert.runModal()
    }

    // MARK: Settings window

    func showSettings(_ page: SettingsPage?) {
        // Leave the page alone while a gesture is being edited, so the edit isn't lost.
        if let page, !model.editingGesture { model.page = page }
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsRoot().environment(model))
            host.sceneBridgingOptions = [.all]
            let window = NSWindow(contentViewController: host)
            window.title = "Octo"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 900, height: 660))
            window.contentMinSize = NSSize(width: 780, height: 540)
            window.isReleasedWhenClosed = false
            // A normal desktop window: it never floats over full-screen apps. If you're in a
            // full-screen app, macOS opens it on the desktop and switches you there.
            // No full screen and no tabs for a settings window (keeps the Window menu short too).
            window.collectionBehavior = [.fullScreenNone]
            window.tabbingMode = .disallowed
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("OctoSettings")
            settingsWindow = window
        }
        // Back to the app you were in when Settings closes (and don't give focus away meanwhile).
        FocusReturn.remember()
        // Become a normal app (in the Dock and app switcher) *before* the window appears.
        // Menu bar apps may put windows on top of a full-screen app; normal apps can't, so the
        // window lands on the Desktop.
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.bringSettingsForward()
        }
    }

    /// True while Octo is re-opening itself, so the "reopen" that causes doesn't loop.
    private var activatingSelf = false
    private var spaceObserver: NSObjectProtocol?

    /// Brings Octo forward, lets macOS switch you to the Desktop, and only *then* shows the window.
    /// - A plain `NSApp.activate()` is often refused for menu bar apps, so Octo opens itself the way
    ///   a Dock click does, which macOS honours (and which switches away from a full-screen app).
    /// - Showing the window before that switch would put it on the full-screen app's Space.
    private func bringSettingsForward() {
        guard let window = settingsWindow else { return }
        activatingSelf = true

        var shown = false
        let show = { [weak self] in
            guard !shown else { return }
            shown = true
            if let observer = self?.spaceObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
                self?.spaceObserver = nil
            }
            // Closed again before it came forward: leave it closed.
            guard self?.settingsWindow === window else {
                self?.activatingSelf = false
                return
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self?.activatingSelf = false
                Log.write("Settings window: visible=\(window.isVisible) onActiveSpace=\(window.isOnActiveSpace) appActive=\(NSApp.isActive)")
            }
        }

        // When macOS finishes moving you to the Desktop, show the window there.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { show() }
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            // Already on the Desktop (no switch needed): show it after a moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { show() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
        updateStatusIcon()
        // Let go of the window and its pages, so nothing keeps running while it's closed (like the
        // Test tab's live view). It's made fresh, at the same place, next time.
        settingsWindow = nil
        DispatchQueue.main.async {
            window.contentViewController = nil
        }
        FocusReturn.giveBack()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.saveNow()
    }
}
