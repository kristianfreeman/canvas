// swift-tools-version: 6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "canvas",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "canvas-server", targets: ["canvas-server"])
    ],
    targets: [
        .target(name: "CanvasCore", path: "Sources/CanvasCore", swiftSettings: v5),
        .target(name: "CanvasApp", dependencies: ["CanvasCore"], path: "Sources/CanvasApp", swiftSettings: v5),
        .executableTarget(
            name: "canvas-server", dependencies: ["CanvasApp"], path: "Sources/canvas-server", swiftSettings: v5),
        .target(name: "TestSupport", dependencies: ["CanvasCore"], path: "Tests/TestSupport", swiftSettings: v5),
        .testTarget(name: "CanvasTests", dependencies: ["CanvasCore"], path: "Tests/CanvasTests", swiftSettings: v5),
        .testTarget(
            name: "BridgeTests", dependencies: ["CanvasApp", "CanvasCore", "TestSupport"], path: "Tests/BridgeTests",
            swiftSettings: v5),
        .testTarget(
            name: "CLITests", dependencies: ["CanvasCore", "TestSupport"], path: "Tests/CLITests", swiftSettings: v5),
        .testTarget(
            name: "NativeTests", dependencies: ["CanvasApp", "CanvasCore", "TestSupport"], path: "Tests/NativeTests",
            swiftSettings: v5),
        .testTarget(
            name: "NativeKitTests", dependencies: ["CanvasApp", "CanvasCore", "TestSupport"],
            path: "Tests/NativeKitTests", swiftSettings: v5)
    ]
)
