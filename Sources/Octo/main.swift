import AppKit

// Octo: small tools in one menu bar app (trackpad gestures, keep awake, clean keyboard, copy text).
//
//   Octo                            run the menu bar app
//   Octo --snapshot D               render every screen to PNG files in folder D, then quit
//   Octo --self-test-copy-text      check text recognition on a drawn image, then quit
//   Octo --self-test-keyboard-lock  check that Clean Keyboard blocks and frees keys (see KeyboardLock.swift)
//   Octo --screenshots D            capture the real panel and Settings window for the README (see ScreenshotMaker.swift)

let arguments = CommandLine.arguments
var snapshotDirectory: String?
if let i = arguments.firstIndex(of: "--snapshot"), i + 1 < arguments.count {
    snapshotDirectory = arguments[i + 1]
}

let app = NSApplication.shared
let delegate = AppDelegate(snapshotDirectory: snapshotDirectory)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
