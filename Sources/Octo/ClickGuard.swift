import AppKit
import QuartzCore
import OctoCore

/// Watches left clicks system-wide (needs Accessibility permission). It does two jobs:
///
/// 1. Multi-finger clicks: when you press the trackpad with 3 fingers over an app that has
///    a 3-finger-click gesture, the normal click is swallowed and the gesture's action runs.
/// 2. Tap to click: macOS adds a click when you tap, so tapping for a gesture would also
///    click whatever is under the pointer. Those clicks are swallowed.
///
/// When it can't tell yet (the click arrives a few milliseconds before the trackpad frame
/// that explains it), it holds the click briefly and either drops it or replays it exactly.
final class ClickGuard {
    static let shared = ClickGuard()

    private(set) var isRunning = false
    private var tap: CFMachPort?
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "octo.clickguard", qos: .userInteractive)
    private var engine: Engine { Engine.shared }

    private enum HoldReason {
        case fingerClick(fingers: Int, binding: GestureBinding, bundleID: String?, appName: String, location: CGPoint)
        case possibleTapClick
        /// A click while 3+ fingers are down, in an app with a multi-finger *tap* gesture:
        /// it may be a click macOS added to that tap.
        case possibleMultiTap
    }

    private struct Hold {
        let token: Int
        let start: Double
        let location: CGPoint
        var reason: HoldReason
        var events: [CGEvent]
        var sawUp = false
        /// A multi-finger click that checked out as a real press: waiting for the release.
        var pressed = false
        /// Turned out to be a drag; being let through.
        var lettingGo = false
    }

    private enum Mode {
        case idle
        /// Swallow events until the press is released, then run `then` (if any).
        case swallowUntilUp(then: (() -> Void)?)
        case holding(Hold)
        case replaying
    }

    private var mode: Mode = .idle
    private var replayBacklog: [CGEvent] = []
    private var nextToken = 0

    /// How long after an accepted gesture tap a click counts as Tap to click's extra click.
    private let tapClickWindow = 0.35
    /// Moving this far (points) while pressed makes it a drag (like three-finger drag), not a click.
    private let dragDistance = 6.0

    func start() -> Bool {
        if isRunning { return true }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: clickGuardCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        tap = port

        // Own thread, so a busy main thread never delays your clicks.
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Octo click guard"
        thread.qualityOfService = .userInteractive
        thread.start()
        isRunning = true
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            recoverFromMissedEvents()
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == ActionPerformer.marker { return pass }

        // For the live view in Test & Tune.
        if type == .leftMouseDown {
            engine.setPressed(true)
        } else if type == .leftMouseUp {
            engine.setPressed(false)
        }

        lock.lock()
        defer { lock.unlock() }

        switch mode {
        case let .swallowUntilUp(then):
            if type == .leftMouseDown {
                // The release went missing (macOS briefly switched this watcher off): start over.
                mode = .idle
                return handleMouseDown(event) ? nil : pass
            }
            if type == .leftMouseUp {
                mode = .idle
                // Run the gesture's action only now that the trackpad is released: macOS ignores
                // a new left click (like ⇧⌘-click) while the button is still held down.
                if let then { queue.asyncAfter(deadline: .now() + 0.015, execute: then) }
            }
            return nil
        case var .holding(hold):
            if let copy = event.copy() { hold.events.append(copy) }
            if type == .leftMouseUp { hold.sawUp = true }
            if case .fingerClick = hold.reason {
                if type == .leftMouseDragged, !hold.lettingGo,
                   hypot(event.location.x - hold.location.x, event.location.y - hold.location.y) > dragDistance {
                    // It's a drag (three-finger drag, or moving while pressing): let it all through.
                    hold.lettingGo = true
                    let token = hold.token
                    queue.async { [weak self] in self?.letGo(token: token) }
                } else if type == .leftMouseUp, hold.pressed, !hold.lettingGo {
                    mode = .idle
                    if let run = action(for: hold.reason) { queue.asyncAfter(deadline: .now() + 0.015, execute: run) }
                    return nil
                }
            }
            mode = .holding(hold)
            return nil
        case .replaying:
            if let copy = event.copy() { replayBacklog.append(copy) }
            return nil
        case .idle:
            guard type == .leftMouseDown else { return pass }
            return handleMouseDown(event) ? nil : pass
        }
    }

    /// Returns true when the click is swallowed or held. Called with the lock held.
    private func handleMouseDown(_ event: CGEvent) -> Bool {
        let now = CACurrentMediaTime()
        engine.noteMouseDown(at: now)

        let fingers = engine.fingersForClick(now: now)
        if fingers >= 3 {
            let gesture = GestureKind.fingerClick(fingers: fingers)
            let location = event.location
            let app = AppLocator.app(at: location) ?? AppLocator.App(bundleID: engine.frontmostApp.bundleID, name: engine.frontmostApp.name)
            if app.bundleID == Engine.ownBundleID {
                // Clicking in Octo's own window (Test & Tune): show it, but keep the click normal.
                engine.logTest(gesture, summary: engine.summary(for: gesture))
                return false
            }
            if let binding = engine.clickBinding(fingers: fingers, bundleID: app.bundleID) {
                // Wait a moment: a real click keeps the fingers down; Tap to click doesn't.
                beginHold(event, now: now, delay: 0.035, reason: .fingerClick(
                    fingers: fingers, binding: binding, bundleID: app.bundleID, appName: app.name, location: location
                ))
                return true
            }
            if engine.blocksTapClicks && engine.hasTapBinding(fingers: fingers, bundleID: app.bundleID) {
                beginHold(event, now: now, delay: 0.12, reason: .possibleMultiTap)
                return true
            }
            if engine.blocksTapClicks && (engine.relevantTap(since: now - tapClickWindow) || engine.hasRelevantCandidate()) {
                // Fingers resting beside a gesture tap: handled as a tap's click below.
            } else {
                engine.log(.noAction, gesture.title, "Nothing set for \(app.name)")
                return false
            }
        }

        guard engine.blocksTapClicks else { return false }
        if engine.relevantTap(since: now - tapClickWindow) {
            mode = .swallowUntilUp(then: nil)
            engine.log(.blocked, "Extra click blocked", "Tap to click added a click to a gesture tap")
            return true
        }
        if engine.hasRelevantCandidate() {
            beginHold(event, now: now, delay: 0.01, reason: .possibleTapClick)
            return true
        }
        return false
    }

    private func beginHold(_ event: CGEvent, now: Double, delay: Double, reason: HoldReason) {
        nextToken += 1
        let token = nextToken
        mode = .holding(Hold(token: token, start: now, location: event.location, reason: reason,
                             events: event.copy().map { [$0] } ?? []))
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.resolve(token: token) }
    }

    /// What a multi-finger click does, once it's released.
    private func action(for reason: HoldReason) -> (() -> Void)? {
        guard case let .fingerClick(fingers, binding, bundleID, appName, location) = reason else { return nil }
        return { [engine] in
            engine.perform(binding, gesture: .fingerClick(fingers: fingers), bundleID: bundleID, appName: appName, at: location)
        }
    }

    private func resolve(token: Int) {
        lock.lock()
        guard case var .holding(hold) = mode, hold.token == token, !hold.lettingGo else {
            lock.unlock()
            return
        }
        let now = CACurrentMediaTime()

        switch hold.reason {
        case let .fingerClick(fingers, _, _, _, _):
            let tapped = engine.relevantTap(since: hold.start - 0.05)
            if engine.fingersForClick(now: now) >= fingers && !tapped {
                // A real press keeps every finger down. Act on release (unless it becomes a drag).
                if hold.sawUp {
                    mode = .idle
                    lock.unlock()
                    if let run = action(for: hold.reason) { queue.asyncAfter(deadline: .now() + 0.015, execute: run) }
                } else {
                    hold.pressed = true
                    mode = .holding(hold)
                    lock.unlock()
                }
            } else if engine.blocksTapClicks && (tapped || engine.hasRelevantCandidate()) {
                // A finger already lifted: this is Tap to click's click for a gesture tap (like
                // the hard-reload double-tap beside two resting fingers), not a 3-finger press.
                hold.reason = .possibleTapClick
                mode = .holding(hold)
                lock.unlock()
                resolve(token: token)
            } else {
                replay(hold.events)
            }

        case .possibleMultiTap:
            if engine.relevantTap(since: hold.start - 0.05) {
                mode = hold.sawUp ? .idle : .swallowUntilUp(then: nil)
                lock.unlock()
                engine.log(.blocked, "Extra click blocked", "macOS added a click to a multi-finger tap")
            } else {
                replay(hold.events)
            }

        case .possibleTapClick:
            if engine.relevantTap(since: hold.start - 0.05) {
                mode = hold.sawUp ? .idle : .swallowUntilUp(then: nil)
                lock.unlock()
                engine.log(.blocked, "Extra click blocked", "Tap to click added a click to a gesture tap")
            } else if !engine.hasRelevantCandidate() || now - hold.start > 0.2 {
                replay(hold.events)
            } else {
                lock.unlock()
                queue.asyncAfter(deadline: .now() + 0.01) { [weak self] in self?.resolve(token: token) }
            }
        }
    }

    /// A held multi-finger click turned into a drag: replay everything so far and step aside.
    private func letGo(token: Int) {
        lock.lock()
        guard case let .holding(hold) = mode, hold.token == token else {
            lock.unlock()
            return
        }
        replay(hold.events)
    }

    /// macOS switched the watcher off for a moment (it does when an app is slow), so a release may
    /// have gone by unseen. If the button is up by now, finish what was waiting for it.
    private func recoverFromMissedEvents() {
        lock.lock()
        guard !CGEventSource.buttonState(.combinedSessionState, button: .left) else {
            lock.unlock()
            return
        }
        switch mode {
        case let .swallowUntilUp(then):
            mode = .idle
            lock.unlock()
            if let then { queue.asyncAfter(deadline: .now() + 0.015, execute: then) }
        case let .holding(hold) where hold.pressed && !hold.lettingGo:
            mode = .idle
            lock.unlock()
            if let run = action(for: hold.reason) { queue.asyncAfter(deadline: .now() + 0.015, execute: run) }
        case let .holding(hold) where !hold.sawUp:
            // Give the app its click back, with the release it would otherwise never get.
            var events = hold.events
            let location = CGEvent(source: nil)?.location ?? hold.location
            if let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left) {
                events.append(up)
            }
            replay(events)
        default:
            lock.unlock()
        }
    }

    /// Posts held events in their original order. Call with the lock held; returns with it released.
    private func replay(_ events: [CGEvent]) {
        mode = .replaying
        var batch = events
        while true {
            lock.unlock()
            for event in batch {
                event.setIntegerValueField(.eventSourceUserData, value: ActionPerformer.marker)
                event.post(tap: .cghidEventTap)
            }
            lock.lock()
            if replayBacklog.isEmpty {
                mode = .idle
                lock.unlock()
                return
            }
            batch = replayBacklog
            replayBacklog.removeAll()
        }
    }
}

private func clickGuardCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<ClickGuard>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}
