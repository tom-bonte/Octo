import CoreGraphics

/// Where the menu bar panel opens. All rectangles and points are in screen coordinates as AppKit
/// uses them (origin at the bottom left of the main screen, y going up).
///
/// The panel used to hang straight off the menu bar icon, but macOS doesn't always report that
/// icon where people see it: while the menu bar hides itself (full screen, or "Automatically hide
/// and show the menu bar"), when the icon sits behind the notch on a crowded menu bar, or when a
/// menu bar organiser (Bartender, Ice) passes the click on. The panel then opened at the left of
/// the screen. So the app works out a fixed spot when the panel opens and hangs the panel there.
public enum PanelPlacement {
    public struct Screen: Sendable {
        public var frame: CGRect
        /// Height of the menu bar along the top of this screen.
        public var menuBarHeight: CGFloat

        public init(frame: CGRect, menuBarHeight: CGFloat) {
            self.frame = frame
            self.menuBarHeight = menuBarHeight
        }
    }

    /// The rectangle the panel's arrow points at; the panel opens just below it.
    /// - Parameters:
    ///   - icon: where macOS says the menu bar icon is, if it says anything.
    ///   - mouse: where the pointer is now.
    ///   - clickedWithMouse: true when a mouse or trackpad click opened the panel (not VoiceOver
    ///     or the keyboard, where the pointer can be anywhere).
    public static func anchor(icon: CGRect?, mouse: CGPoint, clickedWithMouse: Bool, screens: [Screen]) -> CGRect {
        // The usual case: the icon is on a screen, and the click (if any) landed on it.
        if let icon, !icon.isEmpty, screens.contains(where: { $0.frame.contains(icon) }),
           !clickedWithMouse || isOnIcon(mouse, icon) {
            return icon
        }
        // Otherwise the pointer is where the person clicked the icon: open there, just under the
        // menu bar when the pointer is in it.
        var y = mouse.y
        if let screen = screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(mouse) }) {
            let barBottom = screen.frame.maxY - screen.menuBarHeight
            if y >= barBottom { y = barBottom }
        }
        return CGRect(x: mouse.x - 10, y: y, width: 20, height: 1)
    }

    /// The icon's box is a little smaller than the menu bar, and people often click with the
    /// pointer pushed against the top of the screen, so allow some room (most of all above it).
    private static func isOnIcon(_ mouse: CGPoint, _ icon: CGRect) -> Bool {
        mouse.x >= icon.minX - 8 && mouse.x <= icon.maxX + 8 && mouse.y >= icon.minY - 8 && mouse.y <= icon.maxY + 24
    }
}
