// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeLights",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeLights",
            path: "Sources/ClaudeLights"
        )
    ]
)
