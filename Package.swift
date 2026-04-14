// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Maitrics",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "MaitricsCore",
            path: "Sources/MaitricsCore"
        ),
        .executableTarget(
            name: "Maitrics",
            dependencies: ["MaitricsCore"],
            path: "Sources/Maitrics"
        ),
        .testTarget(
            name: "MaitricsCoreTests",
            dependencies: ["MaitricsCore"],
            path: "Tests/MaitricsCoreTests"
        ),
    ]
)
