import AppKit
import Carbon
import OctoCore

/// One system-wide keyboard shortcut (works in every app, needs no permission).
/// Used for Copy Text.
final class HotKey {
    static let shared = HotKey()

    /// Called on the main thread when the shortcut is pressed.
    var onPress: (() -> Void)?

    private var ref: EventHotKeyRef?
    private var handlerInstalled = false
    private(set) var registered: KeyCombo?

    /// Sets the shortcut. Returns false if another app already uses it.
    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        if combo == registered { return true }
        unregister()
        guard combo.isSet else { return true }
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x4F43_544F), id: 1) // "OCTO"
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.modifiers.carbonFlags, id,
                                         GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else {
            Log.write("Shortcut \(combo.display) is already used by another app")
            return false
        }
        ref = newRef
        registered = combo
        Log.write("Copy Text shortcut: \(combo.display)")
        return true
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        registered = nil
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.onPress?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        handlerInstalled = true
    }
}

extension KeyModifiers {
    var carbonFlags: UInt32 {
        var flags = 0
        if contains(.command) { flags |= cmdKey }
        if contains(.shift) { flags |= shiftKey }
        if contains(.option) { flags |= optionKey }
        if contains(.control) { flags |= controlKey }
        return UInt32(flags)
    }
}
