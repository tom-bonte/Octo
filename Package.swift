// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Octo",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: gesture recognition, settings model, action rules. No AppKit, fully testable.
        .target(name: "OctoCore"),
        // The menu bar app: trackpad reading, click handling, actions and the settings window.
        .executableTarget(
            name: "Octo",
            dependencies: ["OctoCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        // Tests run as a small executable (`swift run OctoChecks`), because without full Xcode
        // SwiftPM's test helper doesn't run Swift Testing. The paths point at the Command Line Tools.
        .executableTarget(
            name: "OctoChecks",
            dependencies: ["OctoCore"],
            path: "Tests/OctoCoreTests",
            swiftSettings: [.unsafeFlags([
                "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                "-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing",
            ])],
            linkerSettings: [.unsafeFlags([
                "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                "-framework", "Testing",
                "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
            ])]
        ),
    ]
)
