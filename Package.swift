// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Swift Testing requires macOS 14; the shipping app continues to target macOS 13.
let minimumOS: SupportedPlatform.MacOSVersion = ProcessInfo.processInfo.environment["MYDOCK_TEST_BUILD"] == "1" ? .v14 : .v13

let package = Package(
    name: "MyDock",
    platforms: [.macOS(minimumOS)],
    products: [.executable(name: "MyDock", targets: ["MyDock"])],
    targets: [
        .executableTarget(name: "MyDock"),
        .testTarget(name: "MyDockTests", dependencies: ["MyDock"])
    ]
)
