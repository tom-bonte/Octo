import AppKit
import QuartzCore
import OctoCore

struct LiveTouch: Identifiable, Hashable {
    enum Role: Hashable { case resting, tapping, other, ignored }
    let id: Int32
    /// Millimetres from the left edge.
    let x: Double
    /// Millimetres from the bottom edge.
    let y: Double
    let role: Role
}

struct LogEntry: Identifiable, Hashable {
    enum Kind: Hashable { case action, noAction, blocked, test }
    let id = UUID()
    let date = Date()
    let kind: Kind
    let title: String
    let detail: String
}

/// Connects trackpad frames, the recognizer and the actions.
/// Frames arrive on a private trackpad thread, so all shared state sits behind `lock`.
final class Engine {
    static let shared = Engine()
    static let ownBundleID = Bundle.main.bundleIdentifier ?? "com.tombonte.octo"

    private final class Device {
        let info: TrackpadInfo
        let recognizer: GestureRecognizer
        var lastFrame: Double = 0

        init(info: TrackpadInfo, recognizer: GestureRecognizer) {
            self.info = info
            self.recognizer = recognizer
        }
    }

    private struct Fired {
        let gesture: GestureKind
        let binding: GestureBinding?
        let bundleID: String?
        let appName: String
        /// What the gesture is set to, for Test & Tune.
        let summary: String?
    }

    private let lock = NSLock()
    private var devices: [MTDeviceRef: Device] = [:]
    private var config = Config()
    private var frontmostID: String?
    private var frontmostName = "this app"
    private var lastRelevantTap: Double = -100
    private var liveActive = false
    private var lastLiveSent: Double = 0
    /// The trackpad is pressed down (a physical click is in progress).
    private var pressed = false
    /// Clean Keyboard is on: gestures pause, so wiping the trackpad does nothing.
    private var cleaning = false
    /// Gestures are switched on and not paused for cleaning. Read with the lock held.
    private var gesturesActive: Bool { config.enabled && !cleaning }

    func setCleaning(_ on: Bool) {
        lock.lock()
        cleaning = on
        lock.unlock()
    }
    private var tickScheduled = false
    private let tickQueue = DispatchQueue(label: "octo.engine.tick", qos: .userInteractive)

    let performer = ActionPerformer()
    /// Both are called on the main thread.
    var onLog: ((LogEntry) -> Void)?
    /// Called on the main thread after a gesture's action ran (for the on-screen hint).
    var onPerformed: ((GestureKind, ActionKind) -> Void)?
    var onLive: (([LiveTouch], TrackpadInfo, Bool) -> Void)?

    // MARK: Setup (main thread)

    func setDevices(_ list: [(MTDeviceRef, TrackpadInfo)]) {
        lock.lock()
        defer { lock.unlock() }
        var next: [MTDeviceRef: Device] = [:]
        for (ref, info) in list {
            let recognizer = GestureRecognizer(tuning: config.tuning)
            recognizer.trackpadWidth = info.widthMM
            recognizer.trackpadHeight = info.heightMM
            recognizer.wantsDoubleTap = { [unowned self] resting, side in
                // Called from process()/tick(), which already hold the lock.
                self.gesturesActive
                    && self.config.binding(for: .fixTap(resting: resting, side: side, taps: 2), bundleID: self.frontmostID) != nil
            }
            next[ref] = Device(info: info, recognizer: recognizer)
        }
        devices = next
    }

    func update(config newConfig: Config) {
        lock.lock()
        config = newConfig
        for device in devices.values { device.recognizer.tuning = newConfig.tuning }
        lock.unlock()
    }

    func setFrontmost(bundleID: String?, name: String) {
        lock.lock()
        frontmostID = bundleID
        frontmostName = name
        lock.unlock()
    }

    func setLiveActive(_ active: Bool) {
        lock.lock()
        liveActive = active
        lock.unlock()
    }

    // MARK: Frames (trackpad thread)

    func handleFrame(device ref: MTDeviceRef, touches raw: [RawTouch]) {
        let now = CACurrentMediaTime()
        lock.lock()
        guard let device = devices[ref] else {
            lock.unlock()
            return
        }
        let width = device.info.widthMM, height = device.info.heightMM
        let touching = raw.filter(\.isTouching)
        let points = touching.map { TouchPoint(id: $0.id, x: Double($0.x) * width, y: Double($0.y) * height) }
        device.lastFrame = now
        let fired = collect(device.recognizer.process(time: now, touches: points), now: now)

        var live: [LiveTouch]?
        if liveActive && (now - lastLiveSent > 1.0 / 60 || points.isEmpty) {
            lastLiveSent = now
            let resting = device.recognizer.restingIDs
            let tapping = device.recognizer.tappingIDs
            let ignored = device.recognizer.ignoredIDs
            live = touching.map { t in
                let role: LiveTouch.Role = ignored.contains(t.id) ? .ignored
                    : tapping.contains(t.id) ? .tapping
                    : resting.contains(t.id) ? .resting : .other
                return LiveTouch(id: t.id, x: Double(t.x) * width, y: Double(t.y) * height, role: role)
            }
        }
        let needsTick = device.recognizer.hasPendingTap && !tickScheduled
        if needsTick { tickScheduled = true }
        let tickDelay = config.tuning.doubleTapInterval + 0.03
        let info = device.info
        let isPressed = pressed && !points.isEmpty
        lock.unlock()

        run(fired)
        if let live, let onLive {
            DispatchQueue.main.async { onLive(live, info, isPressed) }
        }
        if needsTick { scheduleTick(after: tickDelay) }
    }

    /// Call with the lock held.
    private func collect(_ events: [RecognizerEvent], now: Double) -> [Fired] {
        var fired: [Fired] = []
        for event in events {
            switch event {
            case let .tapAccepted(resting, side):
                let relevant = gesturesActive && config.hasBinding(bundleID: frontmostID) { gesture in
                    if case let .fixTap(r, s, _) = gesture { return r == resting && s == side }
                    return false
                }
                if relevant { lastRelevantTap = now }
            case let .tapIgnored(resting, side, reason):
                // Show it only where the tap would have done something (or while testing).
                let gesture = GestureKind.fixTap(resting: resting, side: side, taps: 1)
                let relevant = frontmostID == Self.ownBundleID || config.hasBinding(bundleID: frontmostID) { g in
                    if case let .fixTap(r, s, _) = g { return r == resting && s == side }
                    return false
                }
                if gesturesActive && relevant {
                    let why = reason == .typing ? "You were typing a moment ago" : "Fingers too far apart to be one hand"
                    log(.blocked, "Tap ignored: \(gesture.title)", why)
                }
            case let .gesture(gesture):
                guard gesturesActive else { continue }
                let binding = config.binding(for: gesture, bundleID: frontmostID)
                if case .fingerTap = gesture, binding != nil {
                    // So a click macOS might add to this tap gets blocked too.
                    lastRelevantTap = now
                }
                fired.append(Fired(
                    gesture: gesture,
                    binding: binding,
                    bundleID: frontmostID,
                    appName: frontmostName,
                    summary: frontmostID == Self.ownBundleID ? config.summary(for: gesture) : nil
                ))
            }
        }
        return fired
    }

    private func run(_ fired: [Fired]) {
        for f in fired {
            if f.bundleID == Self.ownBundleID {
                logTest(f.gesture, summary: f.summary)
                continue
            }
            guard let binding = f.binding else {
                log(.noAction, f.gesture.title, "Nothing set for \(f.appName)")
                continue
            }
            perform(binding, gesture: f.gesture, bundleID: f.bundleID, appName: f.appName, at: nil)
        }
    }

    func perform(_ binding: GestureBinding, gesture: GestureKind, bundleID: String?, appName: String, at location: CGPoint?) {
        let effect = ActionResolver.effect(for: binding.action, bundleID: bundleID)
        if case let .unsupported(reason) = effect {
            log(.noAction, gesture.title, reason)
            return
        }
        performer.perform(effect, at: location)
        log(.action, gesture.title, "\(binding.action.title) in \(appName)")
        if let onPerformed {
            let action = binding.action
            DispatchQueue.main.async { onPerformed(gesture, action) }
        }
    }

    private func scheduleTick(after delay: Double) {
        tickQueue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.tick() }
    }

    /// Flushes a single tap that was waiting for a possible second tap.
    private func tick() {
        let now = CACurrentMediaTime()
        lock.lock()
        var fired: [Fired] = []
        var stillPending = false
        for device in devices.values {
            fired += collect(device.recognizer.tick(time: now), now: now)
            stillPending = stillPending || device.recognizer.hasPendingTap
        }
        tickScheduled = stillPending
        let delay = config.tuning.doubleTapInterval / 2
        lock.unlock()
        run(fired)
        if stillPending { scheduleTick(after: delay) }
    }

    // MARK: Questions from ClickGuard (event-tap thread)

    /// Only the time of a key press is used, never which key.
    func noteKeyPress(at time: Double) {
        lock.lock()
        for device in devices.values { device.recognizer.noteKeyPress(time: time) }
        lock.unlock()
    }

    func setPressed(_ isPressed: Bool) {
        lock.lock()
        pressed = isPressed
        lock.unlock()
    }

    /// What a gesture is set to (for Test & Tune).
    func summary(for gesture: GestureKind) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return config.summary(for: gesture)
    }

    func logTest(_ gesture: GestureKind, summary: String?) {
        let detail = summary.map { "Set to: \($0)" } ?? "Not set up yet. Add it under Gestures."
        log(.test, gesture.title, detail)
    }

    func noteMouseDown(at time: Double) {
        lock.lock()
        for device in devices.values { device.recognizer.noteMouseDown(time: time) }
        lock.unlock()
    }

    func fingersOnTrackpad(now: Double) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return devices.values.filter { now - $0.lastFrame < 0.25 }.map(\.recognizer.touchCount).max() ?? 0
    }

    /// Fingers pressing the trackpad for a multi-finger click (includes a fingertip near the edge).
    func fingersForClick(now: Double) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return devices.values.filter { now - $0.lastFrame < 0.25 }
            .map { $0.recognizer.fingerCountForClick(now: now) }.max() ?? 0
    }

    func clickBinding(fingers: Int, bundleID: String?) -> GestureBinding? {
        lock.lock()
        defer { lock.unlock() }
        guard gesturesActive else { return nil }
        return config.binding(for: .fingerClick(fingers: fingers), bundleID: bundleID)
    }

    func hasTapBinding(fingers: Int, bundleID: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return gesturesActive && config.binding(for: .fingerTap(fingers: fingers), bundleID: bundleID) != nil
    }

    var blocksTapClicks: Bool {
        lock.lock()
        defer { lock.unlock() }
        return gesturesActive && config.blockTapClicks
    }

    func relevantTap(since time: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return lastRelevantTap >= time
    }

    /// Is a tap underway that a gesture in the front app cares about?
    func hasRelevantCandidate() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard gesturesActive else { return false }
        let counts = Set(devices.values.flatMap(\.recognizer.activeCandidateRestingCounts))
        return counts.contains { count in
            config.hasBinding(bundleID: frontmostID) { gesture in
                if case let .fixTap(resting, _, _) = gesture { return resting == count }
                return false
            }
        }
    }

    var frontmostApp: (bundleID: String?, name: String) {
        lock.lock()
        defer { lock.unlock() }
        return (frontmostID, frontmostName)
    }

    // MARK: Log

    func log(_ kind: LogEntry.Kind, _ title: String, _ detail: String) {
        let entry = LogEntry(kind: kind, title: title, detail: detail)
        guard let onLog else { return }
        DispatchQueue.main.async { onLog(entry) }
    }
}
