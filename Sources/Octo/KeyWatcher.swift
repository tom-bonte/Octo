import AppKit
import QuartzCore

/// Notices *when* you type (not what), so taps right after typing can be ignored.
/// Uses its own event tap on its own thread, so it never slows your typing and a failure
/// here can't affect click handling. Needs the same Accessibility permission.
final class KeyWatcher {
    static let shared = KeyWatcher()
    private(set) var isRunning = false
    private var tap: CFMachPort?

    func start() -> Bool {
        if isRunning { return true }
        let mask = CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: keyWatcherCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        tap = port
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Octo key watcher"
        thread.qualityOfService = .userInteractive
        thread.start()
        isRunning = true
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        } else if type == .keyDown,
                  event.getIntegerValueField(.eventSourceUserData) != ActionPerformer.marker {
            Engine.shared.noteKeyPress(at: CACurrentMediaTime())
        }
        return Unmanaged.passUnretained(event)
    }
}

private func keyWatcherCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<KeyWatcher>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}
