// swift-tools-version:5.10
// Dustbunny has no third-party dependencies on purpose: nothing outside Apple's SDK is linked.
import PackageDescription

let package = Package(
    name: "Dustbunny",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Dustbunny", targets: ["Dustbunny"]),
    ],
    targets: [
        // Pure file-name matching and moving logic. No UI, no persistence, easy to audit and test.
        .target(name: "DustbunnyCore"),
        // Menu bar app: settings, scheduling, animation.
        .executableTarget(name: "Dustbunny", dependencies: ["DustbunnyCore"]),
        .testTarget(name: "DustbunnyCoreTests", dependencies: ["DustbunnyCore"]),
    ]
)
