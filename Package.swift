// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NotchSpace",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchSpace",
            path: "Sources/NotchSpace",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
