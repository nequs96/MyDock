// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyDock",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MyDock", targets: ["MyDock"])],
    targets: [
        .executableTarget(name: "MyDock"),
        .testTarget(name: "MyDockTests", dependencies: ["MyDock"])
    ]
)
