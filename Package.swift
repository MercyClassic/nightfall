// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Nightfall",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Nightfall",
            path: "Sources"
        )
    ]
)
