// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LaunchpadLite",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LaunchpadLite", targets: ["LaunchpadLite"])
    ],
    targets: [
        .executableTarget(
            name: "LaunchpadLite",
            path: "Sources/LaunchpadLite"
        ),
        .testTarget(
            name: "LaunchpadLiteTests",
            dependencies: ["LaunchpadLite"],
            path: "Tests/LaunchpadLiteTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
