import AppKit

/// Octo comes forward for a moment (the menu bar panel, Copy Text's selection, the cleaning
/// screen). Afterwards the keyboard goes back to the app you were using, so ⌘V, shortcuts and
/// gestures work there right away instead of after an extra click.
enum FocusReturn {
    private static var previous: NSRunningApplication?
    /// Bumped whenever Octo comes forward again, so an older give-back is called off.
    private static var generation = 0

    /// Call just before Octo activates itself.
    static func remember() {
        generation += 1
        let front = NSWorkspace.shared.frontmostApplication
        guard front?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        previous = front
    }

    /// Call when Octo's moment is over. Does nothing if you already moved on to another app, or
    /// if one of Octo's own windows (like Settings) is still open.
    static func giveBack() {
        let ticket = generation
        // Let a click into another app finish activating it first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard ticket == generation, let app = previous else { return }
            guard NSApp.isActive, !app.isTerminated else {
                previous = nil // you've moved on already
                return
            }
            // Settings is still open: keep the app in mind for when it closes.
            let ownWindowOpen = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
            guard !ownWindowOpen else { return }
            previous = nil
            NSApp.yieldActivation(to: app)
            app.activate()
        }
    }
}
