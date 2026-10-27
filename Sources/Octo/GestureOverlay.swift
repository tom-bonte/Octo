import AppKit
import SwiftUI
import OctoCore

/// "Show which gesture ran": a small bubble near the bottom of the screen with the gesture's
/// diagram and what it did, for a second and a half. Never takes focus or clicks.
enum GestureHint {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    /// Call on the main thread.
    static func show(gesture: GestureKind, action: ActionKind) {
        hideWork?.cancel()
        let host = NSHostingView(rootView: GestureHintView(gesture: gesture, action: action))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let frame = NSRect(x: visible.midX - size.width / 2, y: visible.minY + 70, width: size.width, height: size.height)

        let panel = self.panel ?? OverlayPanel.make()
        panel.contentView = host
        panel.setFrame(frame, display: true)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        self.panel = panel

        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }) {
                guard panel.alphaValue == 0 else { return } // shown again meanwhile
                panel.orderOut(nil)
                panel.contentView = nil // stops the diagram's animation
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}

struct GestureHintView: View {
    let gesture: GestureKind
    let action: ActionKind

    var body: some View {
        HStack(spacing: 14) {
            GestureDiagram(gesture: gesture, animated: true)
                .frame(width: 70, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Label(action.title, systemImage: action.symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(gesture.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.12).opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
        .padding(10) // room for the shadow
    }
}

/// "Show your fingers on screen": a small live trackpad in the bottom-right corner of the screen,
/// so a screen recording shows the gestures themselves. Drag it anywhere; Octo remembers the spot.
final class FingerOverlay {
    static let shared = FingerOverlay()

    private var panel: NSPanel?
    private var model: AppModel?
    private var watching = false
    private var moveObserver: NSObjectProtocol?
    private static let originKey = "fingerOverlayOrigin"

    func update(visible: Bool, model: AppModel) {
        self.model = model
        if visible { show() } else { hide() }
    }

    private func show() {
        guard panel == nil, let model else { return }
        let host = NSHostingView(rootView: FingerOverlayView().environment(model))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let panel = OverlayPanel.make()
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true
        panel.contentView = host
        // Where you last dragged it (if that's still on a screen), or the bottom-right corner.
        var origin = NSPoint.zero
        if let visible = NSScreen.main?.visibleFrame {
            origin = NSPoint(x: visible.maxX - size.width - 16, y: visible.minY + 16)
        }
        if let saved = UserDefaults.standard.string(forKey: Self.originKey).map(NSPointFromString),
           NSScreen.screens.contains(where: { $0.visibleFrame.contains(NSPoint(x: saved.x + size.width / 2, y: saved.y + size.height / 2)) }) {
            origin = saved
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak panel] _ in
            guard let panel else { return }
            UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.originKey)
        }
        panel.orderFrontRegardless()
        self.panel = panel
        if !watching {
            watching = true
            model.liveViewers += 1
        }
    }

    private func hide() {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        panel?.orderOut(nil)
        panel = nil
        if watching, let model {
            watching = false
            model.liveViewers -= 1
        }
    }
}

struct FingerOverlayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let trackpad = model.liveTrackpad ?? model.trackpads.first
        let width = trackpad?.widthMM ?? 125
        let height = trackpad?.heightMM ?? 77
        TrackpadCanvas(touches: model.liveTouches, pressed: model.livePressed && !model.liveTouches.isEmpty, widthMM: width)
            .aspectRatio(width / height, contentMode: .fit)
            .frame(width: 360)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(white: 0.12).opacity(0.88)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            .environment(\.colorScheme, .dark)
            .padding(10) // room for the shadow
            .help("Your fingers on the trackpad. Drag to move; turn off in Octo → Gestures → Tuning.")
    }
}

/// A floating, see-through panel above other windows (also over full-screen apps) that never
/// becomes the active window.
private enum OverlayPanel {
    static func make() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}
