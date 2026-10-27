import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision

/// Copy Text: drag a box over anything on screen and the text in it is copied.
///
/// 1. A see-through overlay lets you drag a box (Esc or a plain click cancels).
/// 2. That part of the screen is captured with ScreenCaptureKit (needs Screen Recording permission).
/// 3. macOS's built-in text recognition (Vision) reads it, on this Mac, offline.
/// 4. The text (or a QR code's link) goes to the clipboard and a small message confirms it.
final class TextGrabber {
    static let shared = TextGrabber()

    /// Read when copying; set by the app from the settings.
    var keepLineBreaks: () -> Bool = { true }

    private var windows: [NSWindow] = []
    private(set) var isSelecting = false

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Start

    func start() {
        guard !isSelecting else { return }
        guard Self.hasPermission else {
            // Shows macOS's own prompt the first time; after that, point to System Settings.
            CGRequestScreenCaptureAccess()
            Toast.show(
                symbol: "lock.shield",
                title: "Octo needs Screen Recording permission",
                detail: "Turn on Octo in System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
            )
            Log.write("Copy Text: no Screen Recording permission yet")
            return
        }
        isSelecting = true
        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen) { [weak self] rect in
                self?.finish(rect: rect, on: screen)
            } onCancel: { [weak self] in
                self?.closeWindows()
            }
            window.orderFrontRegardless()
            windows.append(window)
        }
        FocusReturn.remember()
        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        (windows.first { $0.frame.contains(mouse) } ?? windows.first)?.makeKey()
        NSCursor.crosshair.set()
    }

    private func closeWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        isSelecting = false
        NSCursor.arrow.set()
        FocusReturn.giveBack()
    }

    // MARK: Capture and read

    /// `rect` is in the screen's own coordinates (points, origin bottom-left of that screen).
    private func finish(rect: CGRect, on screen: NSScreen) {
        closeWindows()
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return }
        // ScreenCaptureKit wants top-left coordinates within the display.
        let sourceRect = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY, width: rect.width, height: rect.height)
        let scale = screen.backingScaleFactor
        let keepLines = keepLineBreaks()

        Task {
            do {
                let image = try await Self.capture(sourceRect, displayID: displayID, scale: scale)
                let result = try TextRecognizer.recognize(image, keepLineBreaks: keepLines)
                await MainActor.run { Self.deliver(result) }
            } catch {
                Log.write("Copy Text failed: \(error.localizedDescription)")
                await MainActor.run {
                    Toast.show(symbol: "exclamationmark.triangle", title: "Couldn't read the screen", detail: error.localizedDescription)
                }
            }
        }
    }

    static func capture(_ rect: CGRect, displayID: CGDirectDisplayID, scale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "Octo", code: 1, userInfo: [NSLocalizedDescriptionKey: "That screen isn't available."])
        }
        // Leave Octo's own floating windows (its messages, overlays, the panel) out of the picture,
        // but keep normal ones: the Guide's "Try It" reads the Guide itself.
        let pid = ProcessInfo.processInfo.processIdentifier
        let ownFloating = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer != 0 }
        let filter = SCContentFilter(display: display, excludingWindows: ownFloating)
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = max(1, Int(rect.width * scale))
        config.height = max(1, Int(rect.height * scale))
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    @MainActor
    private static func deliver(_ result: TextRecognizer.Result?) {
        guard let result else {
            Toast.show(symbol: "text.viewfinder", title: "No text found", detail: "Try a bigger box, or zoom in first.")
            Log.write("Copy Text: no text found")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.text, forType: .string)
        let title = result.fromCode
            ? "Copied the link from a QR code"
            : (result.lines == 1 ? "Copied 1 line" : "Copied \(result.lines) lines")
        let preview = result.text.replacingOccurrences(of: "\n", with: " ")
        Toast.show(symbol: "checkmark.circle.fill", title: title, detail: preview.count > 80 ? String(preview.prefix(80)) + "…" : preview)
        // Only the size, never the text itself, goes to the log.
        Log.write("Copy Text: copied \(result.fromCode ? "a QR code link" : "\(result.lines) lines")")
    }
}

// MARK: - Text recognition

enum TextRecognizer {
    struct Result {
        let text: String
        let lines: Int
        let fromCode: Bool
    }

    /// Reads the text in an image (and any QR code). Nil when there's nothing to copy.
    static func recognize(_ image: CGImage, keepLineBreaks: Bool) throws -> Result? {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.automaticallyDetectsLanguage = true
        let codeRequest = VNDetectBarcodesRequest()
        try VNImageRequestHandler(cgImage: image).perform([textRequest, codeRequest])

        // Top to bottom, then left to right.
        let observations = (textRequest.results ?? []).sorted { a, b in
            abs(a.boundingBox.midY - b.boundingBox.midY) > 0.02
                ? a.boundingBox.midY > b.boundingBox.midY
                : a.boundingBox.minX < b.boundingBox.minX
        }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }

        // A box around just a QR code: copy its link instead of stray text.
        if let payload = codeRequest.results?.compactMap(\.payloadStringValue).first, lines.count <= 2 {
            return Result(text: payload, lines: 1, fromCode: true)
        }
        guard !lines.isEmpty else { return nil }
        return Result(text: lines.joined(separator: keepLineBreaks ? "\n" : " "), lines: lines.count, fromCode: false)
    }
}

// MARK: - Selection overlay

private final class SelectionWindow: NSWindow {
    init(screen: NSScreen, onSelect: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = SelectionView(onSelect: onSelect, onCancel: onCancel)
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    private let onSelect: (CGRect) -> Void
    private let onCancel: () -> Void
    private var start: NSPoint?
    private var current: NSPoint?

    init(onSelect: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onCancel = onCancel
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        guard let rect = selection, rect.width > 6, rect.height > 6 else {
            onCancel() // a plain click cancels
            return
        }
        onSelect(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel() } // Esc
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()
        guard let rect = selection else {
            hint()
            return
        }
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    private func hint() {
        let text = NSAttributedString(string: "Drag over the text to copy · Esc to cancel", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let size = text.size()
        let box = NSRect(x: bounds.midX - size.width / 2 - 14, y: bounds.maxY - 90, width: size.width + 28, height: size.height + 14)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        text.draw(at: NSPoint(x: box.minX + 14, y: box.minY + 7))
    }
}

// MARK: - Small confirmation message

enum Toast {
    private static var window: NSPanel?
    private static var hideWork: DispatchWorkItem?

    /// Call on the main thread.
    static func show(symbol: String, title: String, detail: String?) {
        window?.orderOut(nil)
        hideWork?.cancel()

        let view = ToastView(symbol: symbol, title: title, detail: detail)
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let frame = NSRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 16, width: size.width, height: size.height)

        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = host
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        window = panel

        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }) {
                panel.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (detail == nil ? 1.6 : 2.6), execute: work)
    }
}

private struct ToastView: View {
    let symbol: String
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
    }
}

// MARK: - Self-test

/// `Octo --self-test-copy-text`: draws known text into an image and checks the recognizer reads it.
/// Needs no permission (it doesn't capture the screen).
enum CopyTextSelfTest {
    static func run() {
        let size = NSSize(width: 900, height: 260)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let font = NSFont.systemFont(ofSize: 44, weight: .regular)
        NSAttributedString(string: "Octo copies text 4217", attributes: [.font: font]).draw(at: NSPoint(x: 40, y: 150))
        NSAttributedString(string: "Hola mundo, goedemorgen!", attributes: [.font: font]).draw(at: NSPoint(x: 40, y: 50))
        NSGraphicsContext.restoreGraphicsState()

        guard let image = rep.cgImage, let result = try? TextRecognizer.recognize(image, keepLineBreaks: true) else {
            Log.write("Copy Text self-test FAILED: nothing recognized")
            print("FAILED: nothing recognized")
            return
        }
        let ok = result.lines == 2 && result.text.contains("4217") && result.text.lowercased().contains("goedemorgen")
        let line = "Copy Text self-test \(ok ? "PASSED" : "FAILED"): read \(result.lines) lines: \(result.text.replacingOccurrences(of: "\n", with: " | ")). Screen Recording permission: \(TextGrabber.hasPermission ? "granted" : "not granted yet")"
        Log.write(line)
        print(line)
    }
}
