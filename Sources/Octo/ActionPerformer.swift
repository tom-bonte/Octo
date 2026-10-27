import AppKit
import Carbon
import OctoCore

/// Sends keyboard shortcuts and mouse clicks. Every event carries `marker`,
/// so Octo's own click handling lets them through untouched.
final class ActionPerformer {
    static let marker: Int64 = 0x4F63_746F // "Octo"
    private let queue = DispatchQueue(label: "octo.actions", qos: .userInteractive)

    func perform(_ effect: Effect, at location: CGPoint?) {
        queue.async { [self] in
            switch effect {
            case let .keys(combo): send(combo)
            case .middleClick: click(at: location, button: .center, flags: [], count: 1)
            case .commandClick: click(at: location, button: .left, flags: .maskCommand, count: 1)
            case .shiftCommandClick: click(at: location, button: .left, flags: [.maskCommand, .maskShift], count: 1)
            case .commandDoubleClick: click(at: location, button: .left, flags: .maskCommand, count: 2)
            case .copyTextFromScreen: DispatchQueue.main.async { TextGrabber.shared.start() }
            case .unsupported: break
            }
        }
    }

    private func send(_ combo: KeyCombo) {
        var code = combo.keyCode
        if let character = combo.character, let resolved = KeyLayout.shared.keyCode(for: character) {
            code = resolved
        }
        let source = CGEventSource(stateID: .privateState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown) else { continue }
            event.flags = combo.modifiers.cgFlags
            event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            event.post(tap: .cghidEventTap)
        }
    }

    private func click(at location: CGPoint?, button: CGMouseButton, flags: CGEventFlags, count: Int) {
        let point = location ?? CGEvent(source: nil)?.location ?? .zero
        let source = CGEventSource(stateID: .privateState)
        let types: (CGEventType, CGEventType) = button == .left
            ? (.leftMouseDown, .leftMouseUp)
            : (.otherMouseDown, .otherMouseUp)
        for clickNumber in 1...count {
            for type in [types.0, types.1] {
                guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { continue }
                event.flags = flags
                event.setIntegerValueField(.mouseEventClickState, value: Int64(clickNumber))
                event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
                event.post(tap: .cghidEventTap)
            }
        }
    }
}

extension KeyModifiers {
    var cgFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.shift) { flags.insert(.maskShift) }
        return flags
    }
}

/// Maps characters to key codes for the current keyboard layout, so letter shortcuts
/// land on the right key on AZERTY, QWERTZ and other layouts.
final class KeyLayout {
    static let shared = KeyLayout()
    private let lock = NSLock()
    private var table: [String: UInt16] = [:]

    /// Call on the main thread (the input source APIs require it).
    func startObserving() {
        rebuild()
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuild()
        }
    }

    func keyCode(for character: String) -> UInt16? {
        lock.lock()
        defer { lock.unlock() }
        return table[character.lowercased()]
    }

    private func rebuild() {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return }
        var next: [String: UInt16] = [:]
        bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            // Octo's shortcuts use ⌘, and some layouts change with ⌘ held (like "Dvorak – QWERTY ⌘",
            // or Cyrillic layouts that switch to Latin letters): look at the ⌘ layer first, then the
            // plain one for anything missing.
            let commandLayer = UInt32((cmdKey >> 8) & 0xFF)
            for modifierState in [commandLayer, 0] {
                for code in 0..<128 {
                    var deadKeys: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(
                        layout, UInt16(code), UInt16(kUCKeyActionDown), modifierState, UInt32(LMGetKbdType()),
                        OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, chars.count, &length, &chars
                    )
                    guard status == noErr, length > 0 else { continue }
                    let key = String(utf16CodeUnits: chars, count: length).lowercased()
                    if next[key] == nil { next[key] = UInt16(code) }
                }
            }
        }
        lock.lock()
        table = next
        lock.unlock()
    }
}
