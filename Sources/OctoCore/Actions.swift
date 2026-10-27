import Foundation

public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let shift = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)

    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

public struct KeyCombo: Hashable, Codable, Sendable {
    /// macOS virtual key code (US layout position).
    public var keyCode: UInt16
    public var modifiers: KeyModifiers
    /// Display name of the key, like "R" or "⇥".
    public var key: String
    /// When set, the key is looked up by this character in the current keyboard layout,
    /// so ⌘W stays ⌘W on AZERTY and other layouts. Recorded shortcuts leave it empty.
    public var character: String?

    public init(keyCode: UInt16, key: String, modifiers: KeyModifiers, character: String? = nil) {
        self.keyCode = keyCode
        self.key = key
        self.modifiers = modifiers
        self.character = character
    }

    public static let unset = KeyCombo(keyCode: .max, key: "", modifiers: [])
    public var isSet: Bool { keyCode != .max }
    public var display: String { modifiers.symbols + key }

    /// Whether this works as a system-wide shortcut (like Copy Text's), which takes the keys away
    /// from every app: F1–F12 alone, or a key with ⌘, ⌃ or ⌥, but not the everyday ⌘ shortcuts
    /// (⌘Q, ⌘W, ⌘C, ⌘V, ⌘X, ⌘Z, ⌘A, ⌘H, ⌘M, ⌘Tab, ⌘Space).
    public var isUsableGlobally: Bool {
        guard isSet else { return false }
        let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        if functionKeys.contains(keyCode) { return true }
        guard !modifiers.isDisjoint(with: [.command, .control, .option]) else { return false }
        if modifiers == [.command] {
            let everyday: Set<UInt16> = [12, 13, 8, 9, 7, 6, 0, 4, 46, 48, 49]
            return !everyday.contains(keyCode)
        }
        return true
    }

    static func letter(_ character: String, _ keyCode: UInt16, _ modifiers: KeyModifiers) -> KeyCombo {
        KeyCombo(keyCode: keyCode, key: character.uppercased(), modifiers: modifiers, character: character.lowercased())
    }

    public static let nextTab = KeyCombo(keyCode: 48, key: "⇥", modifiers: [.control])
    public static let previousTab = KeyCombo(keyCode: 48, key: "⇥", modifiers: [.control, .shift])
    public static let firefoxNextTab = KeyCombo(keyCode: 124, key: "→", modifiers: [.command, .option])
    public static let firefoxPreviousTab = KeyCombo(keyCode: 123, key: "←", modifiers: [.command, .option])
    public static let newTab = letter("t", 17, [.command])
    public static let closeTab = letter("w", 13, [.command])
    public static let reopenClosedTab = letter("t", 17, [.command, .shift])
    public static let back = letter("[", 33, [.command])
    public static let forward = letter("]", 30, [.command])
    public static let reload = letter("r", 15, [.command])
    public static let hardReload = letter("r", 15, [.command, .shift])
    public static let safariHardReload = letter("r", 15, [.command, .option])
    /// Default hotkey for Copy Text: ⇧⌘2 (next to the screenshot shortcuts ⇧⌘3/4/5).
    public static let copyTextDefault = KeyCombo(keyCode: 19, key: "2", modifiers: [.command, .shift])
}

/// What a gesture does. Named actions adapt to the app (Safari's hard reload is ⌥⌘R,
/// Chrome's is ⇧⌘R). To add a new action: add a case, give it a title, symbol and id,
/// put it in a group, and say what it does in `ActionResolver`.
public enum ActionKind: Hashable, Codable, Sendable {
    case previousTab, nextTab, newTab, closeTab, reopenClosedTab
    case back, forward, reload, hardReload
    case openInNewTab, openInNewTabAndSwitch, middleClick, commandClick
    case copyTextFromScreen
    case shortcut(KeyCombo)

    public struct Group: Sendable {
        public let title: String
        public let actions: [ActionKind]
    }

    public static let groups: [Group] = [
        Group(title: "Tabs", actions: [.previousTab, .nextTab, .newTab, .closeTab, .reopenClosedTab]),
        Group(title: "Page", actions: [.back, .forward, .reload, .hardReload]),
        Group(title: "Links and clicks", actions: [.openInNewTab, .openInNewTabAndSwitch, .middleClick, .commandClick]),
        Group(title: "Octo tools", actions: [.copyTextFromScreen]),
        Group(title: "Custom", actions: [.shortcut(.unset)]),
    ]

    /// Stable id for pickers (all shortcuts share one id).
    public var id: String {
        switch self {
        case .previousTab: "previousTab"
        case .nextTab: "nextTab"
        case .newTab: "newTab"
        case .closeTab: "closeTab"
        case .reopenClosedTab: "reopenClosedTab"
        case .back: "back"
        case .forward: "forward"
        case .reload: "reload"
        case .hardReload: "hardReload"
        case .openInNewTab: "openInNewTab"
        case .openInNewTabAndSwitch: "openInNewTabAndSwitch"
        case .middleClick: "middleClick"
        case .commandClick: "commandClick"
        case .copyTextFromScreen: "copyTextFromScreen"
        case .shortcut: "shortcut"
        }
    }

    public static func preset(id: String) -> ActionKind? {
        groups.flatMap(\.actions).first { $0.id == id }
    }

    public var title: String {
        switch self {
        case .previousTab: "Previous tab"
        case .nextTab: "Next tab"
        case .newTab: "New tab"
        case .closeTab: "Close tab"
        case .reopenClosedTab: "Reopen closed tab"
        case .back: "Back"
        case .forward: "Forward"
        case .reload: "Reload"
        case .hardReload: "Hard reload"
        case .openInNewTab: "Open link in new tab"
        case .openInNewTabAndSwitch: "Open link in new tab and go to it"
        case .middleClick: "Middle click"
        case .commandClick: "⌘-click"
        case .copyTextFromScreen: "Copy text from screen"
        case let .shortcut(combo): combo.isSet ? "Shortcut \(combo.display)" : "Keyboard shortcut"
        }
    }

    public var symbol: String {
        switch self {
        case .previousTab: "arrow.left.square"
        case .nextTab: "arrow.right.square"
        case .newTab: "plus.square.on.square"
        case .closeTab: "xmark.square"
        case .reopenClosedTab: "arrow.uturn.backward.square"
        case .back: "chevron.backward"
        case .forward: "chevron.forward"
        case .reload: "arrow.clockwise"
        case .hardReload: "arrow.clockwise.circle"
        case .openInNewTab: "plus.rectangle.on.rectangle"
        case .openInNewTabAndSwitch: "arrow.up.forward.square"
        case .middleClick: "computermouse"
        case .commandClick: "command"
        case .copyTextFromScreen: "text.viewfinder"
        case .shortcut: "keyboard"
        }
    }

    public var isValid: Bool {
        if case let .shortcut(combo) = self { return combo.isSet }
        return true
    }

    /// Plain-language note on what is actually sent, shown in the editor.
    public var behaviorNote: String {
        switch self {
        case .previousTab: "Sends ⌃⇧⇥ (⌥⌘← in Firefox). Works in Chrome, Safari and Finder."
        case .nextTab: "Sends ⌃⇥ (⌥⌘→ in Firefox). Works in Chrome, Safari and Finder."
        case .newTab: "Sends ⌘T."
        case .closeTab: "Sends ⌘W."
        case .reopenClosedTab: "Sends ⇧⌘T. Not available in Finder."
        case .back: "Sends ⌘[."
        case .forward: "Sends ⌘]."
        case .reload: "Sends ⌘R. Not available in Finder."
        case .hardReload: "Reloads without the cache: ⌥⌘R in Safari, ⇧⌘R in Chrome and others. Not available in Finder."
        case .openInNewTab: "Opens the link under the pointer in a new tab in the background (middle click; ⌘-click in Safari). In Finder, opens the folder in a new tab."
        case .openInNewTabAndSwitch: "Opens the link under the pointer in a new tab and switches to it (⇧⌘-click). In Finder, opens the folder in a new tab."
        case .middleClick: "Middle-clicks where the pointer is."
        case .commandClick: "Clicks with ⌘ held where the pointer is."
        case .copyTextFromScreen: "Drag a box over any text on screen and Octo copies the text (or the link in a QR code)."
        case .shortcut: "Sends the shortcut you record to the app in front."
        }
    }
}

/// The concrete thing to do in a given app.
public enum Effect: Equatable, Sendable {
    case keys(KeyCombo)
    case middleClick
    case commandClick
    case shiftCommandClick
    case commandDoubleClick
    case copyTextFromScreen
    case unsupported(String)
}

public enum ActionResolver {
    public static func effect(for action: ActionKind, bundleID: String?) -> Effect {
        let id = bundleID ?? ""
        let isFinder = id == KnownApps.finder
        let isSafari = KnownApps.safari.contains(id)
        let isFirefox = KnownApps.firefoxFamily.contains(id)

        switch action {
        case .previousTab: return .keys(isFirefox ? .firefoxPreviousTab : .previousTab)
        case .nextTab: return .keys(isFirefox ? .firefoxNextTab : .nextTab)
        case .newTab: return .keys(.newTab)
        case .closeTab: return .keys(.closeTab)
        case .reopenClosedTab:
            return isFinder ? .unsupported("Finder can't reopen closed tabs") : .keys(.reopenClosedTab)
        case .back: return .keys(.back)
        case .forward: return .keys(.forward)
        case .reload:
            return isFinder ? .unsupported("Finder has no reload") : .keys(.reload)
        case .hardReload:
            if isFinder { return .unsupported("Finder has no hard reload") }
            return .keys(isSafari ? .safariHardReload : .hardReload)
        case .openInNewTab:
            if isFinder { return .commandDoubleClick }
            return isSafari ? .commandClick : .middleClick
        case .openInNewTabAndSwitch:
            return isFinder ? .commandDoubleClick : .shiftCommandClick
        case .middleClick: return .middleClick
        case .commandClick: return .commandClick
        case .copyTextFromScreen: return .copyTextFromScreen
        case let .shortcut(combo):
            return combo.isSet ? .keys(combo) : .unsupported("No shortcut recorded")
        }
    }
}
