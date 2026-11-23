// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Notchling",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Notchling", targets: ["Notchling"]),
        .executable(name: "notchling-mcp", targets: ["notchling-mcp"]),
    ],
    targets: [
        .target(name: "NotchlingCore"),
        .executableTarget(name: "Notchling", dependencies: ["NotchlingCore"]),
        .executableTarget(name: "notchling-mcp", dependencies: ["NotchlingCore"]),
        .testTarget(name: "NotchlingCoreTests", dependencies: ["NotchlingCore"]),
    ]
)
