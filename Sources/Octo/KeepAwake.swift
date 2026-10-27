import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac from sleeping, like Caffeine. It holds one macOS "power assertion" while on,
/// and releases it when turned off. If Octo quits, macOS releases it automatically.
final class KeepAwake {
    static let shared = KeepAwake()

    private var assertion: IOPMAssertionID = 0
    private(set) var isOn = false
    private var screenOn = true

    /// Turns keep-awake on or off. With `screenOn`, the display stays lit too; without it,
    /// only the Mac stays awake and the screen can turn off as usual. Returns the new state.
    @discardableResult
    func set(_ on: Bool, screenOn: Bool) -> Bool {
        if on == isOn && (!on || screenOn == self.screenOn) { return isOn }
        release()
        guard on else { return false }

        let type = screenOn ? "PreventUserIdleDisplaySleep" : "PreventUserIdleSystemSleep"
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Octo: keep Mac awake" as CFString, &id
        )
        guard result == kIOReturnSuccess else {
            Log.write("Keep awake could not start (error \(result))")
            return false
        }
        assertion = id
        isOn = true
        self.screenOn = screenOn
        return true
    }

    private func release() {
        guard isOn else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
        isOn = false
    }
}
