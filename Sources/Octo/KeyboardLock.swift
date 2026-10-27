import AppKit
import IOKit.hidsystem
import SwiftUI

/// Blocks the keyboard so it can be wiped clean, like KeyboardCleanTool.
///
/// Ways out (so you can never get stuck):
/// - hold the on-screen "Hold to unlock" button for a second (trackpad or mouse),
/// - choose "Unlock Keyboard" in Octo's menu,
/// - it unlocks by itself after a few minutes, when the screen locks or the Mac sleeps,
/// - quitting Octo (or Octo crashing) also frees the keyboard, because macOS removes its event tap.
final class KeyboardLock {
    static let shared = KeyboardLock()
    static let autoUnlockAfter: TimeInterval = 5 * 60
    /// Everything that wiping the keyboard or trackpad could set off. The pointer and plain clicks
    /// still work (clicks land on the dark overlay), so you can always reach the unlock button.
    static let blockedTypes: [CGEventType] = [
        .keyDown, .keyUp, .flagsChanged,
        CGEventType(rawValue: 14)!, // media, volume and brightness keys
        .scrollWheel,               // two-finger scrolling
        CGEventType(rawValue: 18)!, // rotate
        CGEventType(rawValue: 19)!, // gesture began
        CGEventType(rawValue: 20)!, // gesture ended
        CGEventType(rawValue: 29)!, // multi-finger gestures (Mission Control, switching desktops)
        CGEventType(rawValue: 30)!, // pinch to zoom
        CGEventType(rawValue: 31)!, // swipe back and forward
        CGEventType(rawValue: 32)!, // smart zoom
    ]

    private(set) var isLocked = false
    private(set) var unlocksAt = Date()
    /// Called on the main thread when the lock turns on or off.
    var onChange: (() -> Void)?

    private var tap: CFMachPort?
    private var tapRunLoop: CFRunLoop?
    private var windows: [NSWindow] = []
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    /// Starts blocking keys. Returns false if macOS doesn't allow it (no Accessibility permission).
    @discardableResult
    func lock(showOverlay: Bool = true) -> Bool {
        if isLocked { return true }
        capsLockWasOn = Self.capsLockIsOn
        let mask = Self.blockedTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: keyboardLockCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.write("Keyboard lock failed: no permission to block keys")
            return false
        }
        tap = port

        // Its own thread, so blocking never depends on the main thread being free.
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            self?.tapRunLoop = CFRunLoopGetCurrent()
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "Octo keyboard lock"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()

        isLocked = true
        Engine.shared.setCleaning(true)
        unlocksAt = Date().addingTimeInterval(Self.autoUnlockAfter)
        timer = Timer.scheduledTimer(withTimeInterval: Self.autoUnlockAfter, repeats: false) { [weak self] _ in
            self?.unlock(reason: "time limit reached")
        }
        unlockWhenScreenLocks()
        if showOverlay { showWindows() }
        Log.write("Keyboard locked for cleaning")
        onChange?()
        return true
    }

    func unlock(reason: String = "unlocked") {
        guard isLocked else { return }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let tapRunLoop { CFRunLoopStop(tapRunLoop) }
        tap = nil
        tapRunLoop = nil
        timer?.invalidate()
        timer = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers = []
        distributedObservers = []
        windows.forEach { $0.orderOut(nil) }
        windows = []
        isLocked = false
        Engine.shared.setCleaning(false)
        // A wipe over Caps Lock still switches it (macOS does that before any app sees the key).
        if Self.capsLockIsOn != capsLockWasOn { Self.setCapsLock(capsLockWasOn) }
        Log.write("Keyboard unlocked (\(reason))")
        onChange?()
        FocusReturn.giveBack()
    }

    private var capsLockWasOn = false

    private static var capsLockIsOn: Bool {
        CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
    }

    private static func setCapsLock(_ on: Bool) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else { return }
        defer { IOServiceClose(connect) }
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), on)
        Log.write("Caps Lock switched back \(on ? "on" : "off") after cleaning")
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Octo's own gesture shortcuts still work while cleaning.
        if event.getIntegerValueField(.eventSourceUserData) == ActionPerformer.marker {
            return Unmanaged.passUnretained(event)
        }
        return nil
    }

    private func unlockWhenScreenLocks() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.unlock(reason: "Mac went to sleep or switched user")
            })
        }
        distributedObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.unlock(reason: "screen locked")
        })
    }

    // MARK: On-screen overlay

    private func showWindows() {
        for screen in NSScreen.screens {
            let window = LockWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.contentView = NSHostingView(rootView: KeyboardLockView(unlocksAt: unlocksAt) { [weak self] in
                self?.unlock(reason: "held the unlock button")
            })
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
        FocusReturn.remember()
        NSApp.activate()
        windows.first?.makeKey()
    }
}

private final class LockWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private func keyboardLockCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<KeyboardLock>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}

/// Dims the screen and shows the unlock button.
struct KeyboardLockView: View {
    let unlocksAt: Date
    let unlock: () -> Void
    @State private var progress = 0.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
            VStack(spacing: 18) {
                Image(systemName: "keyboard")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white)
                Text("Keyboard locked")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                Text("Wipe away: keys, scrolling and trackpad swipes are ignored.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.75))

                HoldToUnlockButton(progress: progress)
                    .padding(.top, 10)
                    .onLongPressGesture(minimumDuration: 1.0, maximumDistance: 80) {
                        unlock()
                    } onPressingChanged: { pressing in
                        withAnimation(pressing ? .linear(duration: 1.0) : .easeOut(duration: 0.2)) {
                            progress = pressing ? 1 : 0
                        }
                    }

                Text("Move the pointer here and hold the button for a second. Unlocks by itself in \(Text(timerInterval: Date.now...unlocksAt, countsDown: true)).")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .padding(44)
            .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.black.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
        }
        .ignoresSafeArea()
    }
}

private struct HoldToUnlockButton: View {
    let progress: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.16))
            GeometryReader { geo in
                Capsule().fill(Color.accentColor).frame(width: max(0, geo.size.width * progress))
            }
            Label("Hold to unlock", systemImage: "lock.open.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
        }
        .frame(width: 280, height: 58)
        .clipShape(Capsule())
        .contentShape(Capsule())
    }
}

/// `Octo --self-test-keyboard-lock` (launched with `open -n`, so it runs with Octo's own
/// permission): sends a harmless test key three times — before locking, while locked, after
/// unlocking — and writes to the log whether each one was let through or blocked.
enum KeyboardLockSelfTest {
    static let testMarker: Int64 = 0x5445_5354 // "TEST"

    final class Counter {
        let lock = NSLock()
        var keys = 0
        var scrolls = 0
    }

    static func run() {
        let counter = Counter()
        let mask = (CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue))
            | (CGEventMask(1) << CGEventMask(CGEventType.keyUp.rawValue))
            | (CGEventMask(1) << CGEventMask(CGEventType.scrollWheel.rawValue))
        guard let observer = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard event.getIntegerValueField(.eventSourceUserData) == KeyboardLockSelfTest.testMarker, let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let counter = Unmanaged<Counter>.fromOpaque(refcon).takeUnretainedValue()
                counter.lock.lock()
                if type == .keyDown { counter.keys += 1 }
                if type == .scrollWheel { counter.scrolls += 1 }
                counter.lock.unlock()
                return nil // keep the test events away from apps
            },
            userInfo: Unmanaged.passUnretained(counter).toOpaque()
        ) else {
            Log.write("Keyboard lock self-test: couldn't watch keys (no permission)")
            return
        }
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, observer, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: observer, enable: true)
            CFRunLoopRun()
        }
        thread.start()
        wait(0.3)

        func sendTestEvents() {
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 79, keyDown: down) // F18: does nothing
                event?.setIntegerValueField(.eventSourceUserData, value: testMarker)
                event?.post(tap: .cghidEventTap)
            }
            let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0)
            scroll?.setIntegerValueField(.eventSourceUserData, value: testMarker)
            scroll?.post(tap: .cghidEventTap)
            wait(0.4)
        }
        func seen() -> (keys: Int, scrolls: Int) {
            counter.lock.lock()
            defer { counter.lock.unlock() }
            return (counter.keys, counter.scrolls)
        }
        func describe(_ now: (keys: Int, scrolls: Int), _ earlier: (keys: Int, scrolls: Int)) -> String {
            let key = now.keys > earlier.keys ? "key got through" : "key blocked"
            let scroll = now.scrolls > earlier.scrolls ? "scroll got through" : "scroll blocked"
            return "\(key), \(scroll)"
        }

        let start = seen()
        sendTestEvents()
        let before = seen()
        let locked = KeyboardLock.shared.lock(showOverlay: false)
        sendTestEvents()
        let during = seen()
        KeyboardLock.shared.unlock(reason: "self-test")
        sendTestEvents()
        let after = seen()
        CGEvent.tapEnable(tap: observer, enable: false)

        let ok = locked && before == (1, 1) && during == before && after == (2, 2)
        Log.write("Keyboard lock self-test \(ok ? "PASSED" : "FAILED"): before lock \(describe(before, start)); "
            + "while locked \(describe(during, before)); after unlock \(describe(after, during))")
    }

    private static func wait(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
