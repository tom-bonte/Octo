import Foundation
import Testing
import OctoCore

extension Config {
    mutating func setEnabledForTest(_ id: UUID, _ enabled: Bool) {
        if let i = bindings.firstIndex(where: { $0.id == id }) { bindings[i].enabled = enabled }
    }
}

@Suite("Settings and per-app rules")
struct ConfigTests {
    let chrome = "com.google.Chrome"
    let safari = "com.apple.Safari"
    let xcode = "com.apple.dt.Xcode"

    @Test func defaultsCoverTheStartingGestures() {
        let c = Config()
        #expect(c.binding(for: .fixTap(resting: 1, side: .left, taps: 1), bundleID: chrome)?.action == .previousTab)
        #expect(c.binding(for: .fixTap(resting: 1, side: .right, taps: 1), bundleID: KnownApps.finder)?.action == .nextTab)
        #expect(c.binding(for: .fingerClick(fingers: 3), bundleID: safari)?.action == .openInNewTab)
        #expect(c.binding(for: .fingerClick(fingers: 4), bundleID: chrome)?.action == .openInNewTabAndSwitch)
        #expect(c.binding(for: .fingerTap(fingers: 4), bundleID: chrome) == nil)
        #expect(c.binding(for: .fixTap(resting: 2, side: .left, taps: 2), bundleID: chrome)?.action == .hardReload)
        #expect(c.binding(for: .fixTap(resting: 2, side: .left, taps: 2), bundleID: KnownApps.finder) == nil)
        #expect(c.binding(for: .fixTap(resting: 1, side: .right, taps: 1), bundleID: xcode) == nil)
    }

    @Test func specificAppBeatsBrowsersBeatsAllApps() {
        var c = Config()
        let g = GestureKind.fixTap(resting: 1, side: .right, taps: 2)
        c.bindings = [
            GestureBinding(gesture: g, action: .reload, scope: AppScope(allApps: true)),
            GestureBinding(gesture: g, action: .newTab, scope: .browsersOnly),
            GestureBinding(gesture: g, action: .closeTab, scope: AppScope(apps: [AppRef(bundleID: chrome, name: "Chrome")])),
        ]
        #expect(c.binding(for: g, bundleID: chrome)?.action == .closeTab)
        #expect(c.binding(for: g, bundleID: safari)?.action == .newTab)
        #expect(c.binding(for: g, bundleID: xcode)?.action == .reload)
    }

    @Test func disabledSettingsAreIgnored() {
        var c = Config()
        for i in c.bindings.indices { c.bindings[i].enabled = false }
        #expect(c.binding(for: .fingerClick(fingers: 3), bundleID: chrome) == nil)
    }

    @Test func excludedBrowserIsNotABrowser() {
        var c = Config()
        c.excludedBrowsers = [safari]
        #expect(!c.isBrowser(safari))
        #expect(c.isBrowser(chrome))
        #expect(c.binding(for: .fingerClick(fingers: 3), bundleID: safari) == nil)
    }

    @Test func actionsAdaptToTheApp() {
        #expect(ActionResolver.effect(for: .hardReload, bundleID: safari) == .keys(.safariHardReload))
        #expect(ActionResolver.effect(for: .hardReload, bundleID: chrome) == .keys(.hardReload))
        if case .unsupported = ActionResolver.effect(for: .hardReload, bundleID: KnownApps.finder) {} else {
            Issue.record("Finder has no hard reload")
        }
        #expect(ActionResolver.effect(for: .openInNewTab, bundleID: chrome) == .middleClick)
        #expect(ActionResolver.effect(for: .openInNewTab, bundleID: safari) == .commandClick)
        #expect(ActionResolver.effect(for: .openInNewTab, bundleID: KnownApps.finder) == .commandDoubleClick)
        #expect(ActionResolver.effect(for: .nextTab, bundleID: "org.mozilla.firefox") == .keys(.firefoxNextTab))
        #expect(ActionResolver.effect(for: .openInNewTabAndSwitch, bundleID: chrome) == .shiftCommandClick)
        #expect(ActionResolver.effect(for: .openInNewTabAndSwitch, bundleID: safari) == .shiftCommandClick)
        #expect(ActionResolver.effect(for: .openInNewTabAndSwitch, bundleID: KnownApps.finder) == .commandDoubleClick)
        #expect(ActionResolver.effect(for: .copyTextFromScreen, bundleID: chrome) == .copyTextFromScreen)
        #expect(ActionKind.preset(id: "copyTextFromScreen") == .copyTextFromScreen)
    }

    @Test func roundTripsThroughJSON() throws {
        var c = Config()
        c.tuning.tapMaxDuration = 0.3
        c.bindings.append(GestureBinding(
            gesture: .fixTap(resting: 1, side: .right, taps: 2),
            action: .shortcut(KeyCombo(keyCode: 13, key: "W", modifiers: [.command])),
            scope: AppScope(apps: [AppRef(bundleID: xcode, name: "Xcode")])
        ))
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(Config.self, from: data)
        #expect(back == c)
    }

    @Test func skipsUnknownGesturesAndFillsMissingValues() throws {
        let json = """
        {
          "bindings": [
            { "gesture": { "pinkyToIndex": {} }, "action": { "nextTab": {} }, "scope": { "browsers": true } },
            { "gesture": { "fingerClick": { "fingers": 3 } }, "action": { "middleClick": {} }, "scope": { "browsers": true } }
          ],
          "tuning": { "tapMaxDuration": 0.2 }
        }
        """
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(c.bindings.count == 1)
        #expect(c.bindings.first?.gesture == .fingerClick(fingers: 3))
        #expect(c.tuning.tapMaxDuration == 0.2)
        #expect(c.tuning.doubleTapInterval == Tuning().doubleTapInterval)
        #expect(c.enabled)
        #expect(c.awakeKeepsScreenOn)
        #expect(c.copyTextHotkey == .copyTextDefault)
        #expect(c.copyTextKeepsLineBreaks)
    }

    @Test func summarizesWhatAGestureDoes() {
        var c = Config()
        let tapRight = GestureKind.fixTap(resting: 1, side: .right, taps: 1)
        #expect(c.summary(for: tapRight, detailed: false) == "Next tab")
        #expect(c.summary(for: tapRight) == "Next tab in Browsers, Finder")
        #expect(c.summary(for: .fingerTap(fingers: 3)) == nil)
        let id = c.bindings.first { $0.gesture == tapRight }!.id
        #expect(c.summary(for: tapRight, excluding: id) == nil)
        c.setEnabledForTest(id, false)
        #expect(c.summary(for: tapRight, detailed: false) == "Next tab (off)")
    }

    @Test func findsOverlappingSettings() {
        let c = Config()
        let extra = GestureBinding(
            gesture: .fixTap(resting: 1, side: .right, taps: 1),
            action: .closeTab,
            scope: AppScope(apps: [AppRef(bundleID: chrome, name: "Chrome")])
        )
        #expect(c.overlaps(with: extra).map(\.action) == [.nextTab])
        let elsewhere = GestureBinding(gesture: extra.gesture, action: .closeTab, scope: AppScope(apps: [AppRef(bundleID: xcode, name: "Xcode")]))
        #expect(c.overlaps(with: elsewhere).isEmpty)
    }
}

@Suite("Reading the settings file")
struct ConfigFileTests {
    @Test func oneBadValueKeepsEverythingElse() throws {
        // A hand-edited file: a number written as text, an app without a name.
        let json = """
        {
          "enabled": false,
          "tuning": { "typingGuard": "0.5", "tapMaxDuration": 0.3 },
          "extraBrowsers": [ { "bundleID": "com.example.browser" }, { "bundleID": "com.example.ok", "name": "OK" } ],
          "bindings": [ { "gesture": "nonsense" } ],
          "awakeKeepsScreenOn": "yes"
        }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.enabled == false)
        #expect(config.tuning.tapMaxDuration == 0.3)
        #expect(config.tuning.typingGuard == Tuning().typingGuard)
        #expect(config.extraBrowsers.map(\.bundleID) == ["com.example.ok"])
        #expect(config.bindings.isEmpty) // the one broken gesture is skipped
        #expect(config.awakeKeepsScreenOn == true)
    }

    @Test func savedSettingsComeBackTheSame() throws {
        var config = Config()
        config.enabled = false
        config.tuning.edgeMargin = 0.1
        config.copyTextHotkey = .unset
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data) == config)
    }
}

@Suite("System-wide shortcuts")
struct GlobalShortcutTests {
    @Test func needsCommandControlOrOption() {
        #expect(KeyCombo.copyTextDefault.isUsableGlobally) // ⇧⌘2
        #expect(KeyCombo(keyCode: 0, key: "A", modifiers: [.control, .option]).isUsableGlobally)
        #expect(!KeyCombo(keyCode: 0, key: "A", modifiers: []).isUsableGlobally)
        #expect(!KeyCombo(keyCode: 0, key: "A", modifiers: [.shift]).isUsableGlobally)
        #expect(!KeyCombo(keyCode: 49, key: "Space", modifiers: []).isUsableGlobally)
        #expect(!KeyCombo.unset.isUsableGlobally)
    }

    @Test func functionKeysWorkAlone() {
        #expect(KeyCombo(keyCode: 122, key: "F1", modifiers: []).isUsableGlobally)
        #expect(KeyCombo(keyCode: 111, key: "F12", modifiers: []).isUsableGlobally)
    }

    @Test func everydayCommandShortcutsAreRefused() {
        for (code, key) in [(12, "Q"), (13, "W"), (8, "C"), (9, "V"), (7, "X"), (6, "Z"), (0, "A"), (48, "⇥"), (49, "Space")] {
            #expect(!KeyCombo(keyCode: UInt16(code), key: key, modifiers: [.command]).isUsableGlobally, "⌘\(key)")
        }
        // With another modifier they're fine (⇧⌘Z is not ⌘Z).
        #expect(KeyCombo(keyCode: 6, key: "Z", modifiers: [.command, .shift]).isUsableGlobally)
    }
}
