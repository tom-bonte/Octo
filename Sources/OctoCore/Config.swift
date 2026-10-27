import Foundation

public struct AppRef: Codable, Hashable, Identifiable, Sendable {
    public var bundleID: String
    public var name: String
    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public enum KnownApps {
    public static let finder = "com.apple.finder"
    public static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    public static let firefoxFamily: Set<String> = [
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "app.zen-browser.zen", "net.waterfox.waterfox",
    ]
    public static let browsers: [AppRef] = [
        AppRef(bundleID: "com.apple.Safari", name: "Safari"),
        AppRef(bundleID: "com.apple.SafariTechnologyPreview", name: "Safari Technology Preview"),
        AppRef(bundleID: "com.google.Chrome", name: "Google Chrome"),
        AppRef(bundleID: "com.google.Chrome.beta", name: "Google Chrome Beta"),
        AppRef(bundleID: "com.google.Chrome.dev", name: "Google Chrome Dev"),
        AppRef(bundleID: "com.google.Chrome.canary", name: "Google Chrome Canary"),
        AppRef(bundleID: "org.chromium.Chromium", name: "Chromium"),
        AppRef(bundleID: "company.thebrowser.Browser", name: "Arc"),
        AppRef(bundleID: "company.thebrowser.dia", name: "Dia"),
        AppRef(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge"),
        AppRef(bundleID: "com.brave.Browser", name: "Brave"),
        AppRef(bundleID: "com.operasoftware.Opera", name: "Opera"),
        AppRef(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi"),
        AppRef(bundleID: "com.kagi.kagimacOS", name: "Orion"),
        AppRef(bundleID: "org.mozilla.firefox", name: "Firefox"),
        AppRef(bundleID: "org.mozilla.firefoxdeveloperedition", name: "Firefox Developer Edition"),
        AppRef(bundleID: "org.mozilla.nightly", name: "Firefox Nightly"),
        AppRef(bundleID: "app.zen-browser.zen", name: "Zen"),
        AppRef(bundleID: "com.duckduckgo.macos.browser", name: "DuckDuckGo"),
    ]
}

/// Which apps a gesture works in.
public struct AppScope: Codable, Hashable, Sendable {
    public var allApps: Bool
    public var browsers: Bool
    public var finder: Bool
    public var apps: [AppRef]

    public init(allApps: Bool = false, browsers: Bool = false, finder: Bool = false, apps: [AppRef] = []) {
        self.allApps = allApps
        self.browsers = browsers
        self.finder = finder
        self.apps = apps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        allApps = try c.decodeIfPresent(Bool.self, forKey: .allApps) ?? false
        browsers = try c.decodeIfPresent(Bool.self, forKey: .browsers) ?? false
        finder = try c.decodeIfPresent(Bool.self, forKey: .finder) ?? false
        apps = try c.decodeIfPresent([AppRef].self, forKey: .apps) ?? []
    }

    public static let browsersAndFinder = AppScope(browsers: true, finder: true)
    public static let browsersOnly = AppScope(browsers: true)

    public var isEmpty: Bool { !allApps && !browsers && !finder && apps.isEmpty }

    public var labels: [String] {
        var out: [String] = []
        if allApps { out.append("All apps") }
        if browsers { out.append("Browsers") }
        if finder { out.append("Finder") }
        out += apps.map(\.name)
        return out
    }
}

public struct GestureBinding: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var gesture: GestureKind
    public var action: ActionKind
    public var scope: AppScope
    public var enabled: Bool

    public init(id: UUID = UUID(), gesture: GestureKind, action: ActionKind, scope: AppScope, enabled: Bool = true) {
        self.id = id
        self.gesture = gesture
        self.action = action
        self.scope = scope
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        gesture = try c.decode(GestureKind.self, forKey: .gesture)
        action = try c.decode(ActionKind.self, forKey: .action)
        scope = try c.decodeIfPresent(AppScope.self, forKey: .scope) ?? AppScope()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

/// Thresholds for telling taps from rests, slides and clicks. Distances are in millimetres.
public struct Tuning: Codable, Equatable, Sendable {
    /// A tap must lift within this many seconds.
    public var tapMaxDuration = 0.25
    /// The tapping finger may slide this far.
    public var tapMaxMovement = 3.0
    /// Fingers count as resting once they've been down this long.
    public var restMinDuration = 0.10
    /// Resting fingers may drift this far during a tap.
    public var restMaxMovement = 3.0
    /// Gap allowed between the first tap lifting and the second landing.
    public var doubleTapInterval = 0.30
    /// The second tap must land this close to the first.
    public var doubleTapMaxDistance = 15.0
    /// How far from horizontal (in degrees) a tap may be, measured from the nearest resting finger.
    public var maxTapAngle = 50.0

    // Against accidental taps (a palm and a stray finger while typing):
    /// Taps are ignored for this many seconds after a key press. 0 turns it off.
    public var typingGuard = 0.6
    /// The tapping finger must be at most this far from the nearest resting finger (one hand).
    public var maxTapDistance = 45.0
    /// Touches that start within this fraction of the trackpad's width/height from any edge are ignored.
    public var edgeMargin = 0.15

    public init() {}

    public init(from decoder: Decoder) throws {
        let d = Tuning()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tapMaxDuration = (try? c.decodeIfPresent(Double.self, forKey: .tapMaxDuration)) ?? d.tapMaxDuration
        tapMaxMovement = (try? c.decodeIfPresent(Double.self, forKey: .tapMaxMovement)) ?? d.tapMaxMovement
        restMinDuration = (try? c.decodeIfPresent(Double.self, forKey: .restMinDuration)) ?? d.restMinDuration
        restMaxMovement = (try? c.decodeIfPresent(Double.self, forKey: .restMaxMovement)) ?? d.restMaxMovement
        doubleTapInterval = (try? c.decodeIfPresent(Double.self, forKey: .doubleTapInterval)) ?? d.doubleTapInterval
        doubleTapMaxDistance = (try? c.decodeIfPresent(Double.self, forKey: .doubleTapMaxDistance)) ?? d.doubleTapMaxDistance
        maxTapAngle = (try? c.decodeIfPresent(Double.self, forKey: .maxTapAngle)) ?? d.maxTapAngle
        typingGuard = (try? c.decodeIfPresent(Double.self, forKey: .typingGuard)) ?? d.typingGuard
        maxTapDistance = (try? c.decodeIfPresent(Double.self, forKey: .maxTapDistance)) ?? d.maxTapDistance
        edgeMargin = (try? c.decodeIfPresent(Double.self, forKey: .edgeMargin)) ?? d.edgeMargin
    }
}

/// Everything the user can set. Saved as JSON. Unknown or broken entries are skipped
/// on load, so older and newer versions of the app can share the file.
public struct Config: Codable, Equatable, Sendable {
    public var enabled = true
    /// Swallow the click that "Tap to click" adds when you tap for a gesture.
    public var blockTapClicks = true
    public var bindings: [GestureBinding] = Config.defaultBindings
    public var tuning = Tuning()
    /// Known browsers the user switched off.
    public var excludedBrowsers: [String] = []
    /// Apps the user added to the Browsers group.
    public var extraBrowsers: [AppRef] = []
    /// Keep awake: keep the screen on too (not just the Mac).
    public var awakeKeepsScreenOn = true
    /// Copy Text: the global hotkey (unset = no hotkey).
    public var copyTextHotkey = KeyCombo.copyTextDefault
    /// Copy Text: keep line breaks (otherwise lines are joined into one paragraph).
    public var copyTextKeepsLineBreaks = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Each setting on its own: one broken or unknown value falls back to its default
        // instead of taking every other setting down with it.
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        blockTapClicks = (try? c.decodeIfPresent(Bool.self, forKey: .blockTapClicks)) ?? true
        if let lossy = try? c.decodeIfPresent([Lossy<GestureBinding>].self, forKey: .bindings) {
            bindings = lossy.compactMap(\.value)
        } else {
            bindings = Config.defaultBindings
        }
        tuning = (try? c.decodeIfPresent(Tuning.self, forKey: .tuning)) ?? Tuning()
        excludedBrowsers = (try? c.decodeIfPresent([Lossy<String>].self, forKey: .excludedBrowsers))?.compactMap(\.value) ?? []
        extraBrowsers = (try? c.decodeIfPresent([Lossy<AppRef>].self, forKey: .extraBrowsers))?.compactMap(\.value) ?? []
        awakeKeepsScreenOn = (try? c.decodeIfPresent(Bool.self, forKey: .awakeKeepsScreenOn)) ?? true
        copyTextHotkey = (try? c.decodeIfPresent(KeyCombo.self, forKey: .copyTextHotkey)) ?? .copyTextDefault
        copyTextKeepsLineBreaks = (try? c.decodeIfPresent(Bool.self, forKey: .copyTextKeepsLineBreaks)) ?? true
    }

    public static var defaultBindings: [GestureBinding] {
        [
            GestureBinding(gesture: .fixTap(resting: 1, side: .left, taps: 1), action: .previousTab, scope: .browsersAndFinder),
            GestureBinding(gesture: .fixTap(resting: 1, side: .right, taps: 1), action: .nextTab, scope: .browsersAndFinder),
            GestureBinding(gesture: .fingerClick(fingers: 3), action: .openInNewTab, scope: .browsersAndFinder),
            GestureBinding(gesture: .fingerClick(fingers: 4), action: .openInNewTabAndSwitch, scope: .browsersAndFinder),
            GestureBinding(gesture: .fixTap(resting: 2, side: .left, taps: 2), action: .hardReload, scope: .browsersOnly),
        ]
    }

    // MARK: Matching

    public func isBrowser(_ bundleID: String) -> Bool {
        if excludedBrowsers.contains(bundleID) { return false }
        return KnownApps.browsers.contains { $0.bundleID == bundleID }
            || extraBrowsers.contains { $0.bundleID == bundleID }
    }

    /// 0 means the scope doesn't cover the app. Higher means more specific:
    /// a named app (3) beats Browsers or Finder (2), which beat All apps (1).
    public func specificity(of scope: AppScope, for bundleID: String?) -> Int {
        guard let id = bundleID else { return scope.allApps ? 1 : 0 }
        if scope.apps.contains(where: { $0.bundleID == id }) { return 3 }
        if scope.finder && id == KnownApps.finder { return 2 }
        if scope.browsers && isBrowser(id) { return 2 }
        if scope.allApps { return 1 }
        return 0
    }

    /// The setting that applies to this gesture in this app, if any.
    public func binding(for gesture: GestureKind, bundleID: String?) -> GestureBinding? {
        var best: GestureBinding?
        var bestScore = 0
        for b in bindings where b.enabled && b.gesture == gesture {
            let score = specificity(of: b.scope, for: bundleID)
            if score > bestScore {
                best = b
                bestScore = score
            }
        }
        return best
    }

    public func hasBinding(bundleID: String?, where matches: (GestureKind) -> Bool) -> Bool {
        bindings.contains { $0.enabled && matches($0.gesture) && specificity(of: $0.scope, for: bundleID) > 0 }
    }

    /// What a gesture is set to, for display. Short: "Next tab". Detailed: "Next tab in Browsers, Finder".
    /// Nil when the gesture isn't used.
    public func summary(for gesture: GestureKind, excluding id: UUID? = nil, detailed: Bool = true) -> String? {
        let matches = bindings.filter { $0.gesture == gesture && $0.id != id }
        guard !matches.isEmpty else { return nil }
        return matches.map { b in
            var text = b.action.title
            if detailed { text += " in \(b.scope.labels.joined(separator: ", "))" }
            if !b.enabled { text += " (off)" }
            return text
        }.joined(separator: detailed ? "; " : ", ")
    }

    /// Other enabled settings for the same gesture that cover some of the same apps.
    public func overlaps(with binding: GestureBinding) -> [GestureBinding] {
        bindings.filter { other in
            other.id != binding.id && other.enabled && other.gesture == binding.gesture
                && scopesOverlap(other.scope, binding.scope)
        }
    }

    private func scopesOverlap(_ a: AppScope, _ b: AppScope) -> Bool {
        if a.allApps || b.allApps { return true }
        if a.browsers && b.browsers { return true }
        if a.finder && b.finder { return true }
        let aIDs = Set(a.apps.map(\.bundleID)), bIDs = Set(b.apps.map(\.bundleID))
        if !aIDs.isDisjoint(with: bIDs) { return true }
        if a.browsers && bIDs.contains(where: isBrowser) { return true }
        if b.browsers && aIDs.contains(where: isBrowser) { return true }
        if a.finder && bIDs.contains(KnownApps.finder) { return true }
        if b.finder && aIDs.contains(KnownApps.finder) { return true }
        return false
    }
}

/// Decodes an element if it can, and skips it otherwise.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
