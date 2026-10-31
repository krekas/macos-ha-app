// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HAApp",
    platforms: [.macOS(.v26)],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "HAAppKit"),
        .executableTarget(
            name: "HAApp",
            dependencies: ["HAAppKit"],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "HAAppKitTests", dependencies: ["HAAppKit"]),
    ]
)
