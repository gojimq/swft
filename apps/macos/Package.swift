// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Swft",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Swft", targets: ["Swft"]),
        .library(name: "SwftKit", targets: ["SwftKit"]),
        .library(name: "SwftDesign", targets: ["SwftDesign"]),
    ],
    targets: [
        // Backend client: WebSocket protocol, models, bundled-server process. Owned by the engineering track.
        .target(name: "SwftKit"),
        // Design system: tokens, fonts, reusable components. Owned by the design track.
        .target(name: "SwftDesign", resources: [.process("Resources")]),
        // App: windows, screens, view models.
        .executableTarget(name: "Swft", dependencies: ["SwftKit", "SwftDesign"]),
        .testTarget(name: "SwftKitTests", dependencies: ["SwftKit"]),
        .testTarget(name: "SwftTests", dependencies: ["Swft", "SwftKit"]),
    ]
)
