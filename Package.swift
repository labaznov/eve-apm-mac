// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EVEAPMMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "EVEAPMMac",
            path: "Sources/EVEAPMMac"
        ),
        .testTarget(
            name: "EVEAPMMacTests",
            dependencies: ["EVEAPMMac"],
            path: "Tests/EVEAPMMacTests"
        )
    ]
)
