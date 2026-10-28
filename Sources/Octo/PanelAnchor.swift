import AppKit
import OctoCore

/// The spot the menu bar panel hangs from: a small invisible window placed under the Octo icon
/// when the panel opens (see PanelPlacement for why). It stays put while the panel is open, so
/// the panel doesn't jump when the menu bar hides itself or the menu bar icons move.
final class PanelAnchor {
    private lazy var window: NSPanel = {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 20, height: 1),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true // clicks go through to the menu bar icon underneath
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return window
    }()

    /// Places the anchor under the menu bar icon (or where the click was) and returns the view
    /// to show the panel from.
    func view(under button: NSStatusBarButton) -> NSView {
        let icon = button.window.map { $0.convertToScreen(button.convert(button.bounds, to: nil)) }
        let mouseClicks: [NSEvent.EventType] = [.leftMouseUp, .rightMouseUp, .leftMouseDown, .rightMouseDown]
        let clickedWithMouse = NSApp.currentEvent.map { mouseClicks.contains($0.type) } ?? false
        let screens = NSScreen.screens.map {
            PanelPlacement.Screen(frame: $0.frame, menuBarHeight: Self.menuBarHeight(of: $0))
        }
        let rect = PanelPlacement.anchor(icon: icon, mouse: NSEvent.mouseLocation,
                                         clickedWithMouse: clickedWithMouse, screens: screens)
        window.setFrame(rect, display: false)
        window.orderFrontRegardless()
        return window.contentView!
    }

    func hide() {
        window.orderOut(nil)
    }

    /// The menu bar's height on a screen. visibleFrame leaves it out unless it hides itself; the
    /// notch area (safeAreaInsets) covers the taller menu bar of MacBooks with a notch.
    private static func menuBarHeight(of screen: NSScreen) -> CGFloat {
        max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top, NSStatusBar.system.thickness)
    }
}
