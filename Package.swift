// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AINotch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AINotch", targets: ["AINotch"])
    ],
    targets: [
        .executableTarget(
            name: "AINotch",
            path: "Sources/AINotch"
        ),
        .testTarget(
            name: "AINotchTests",
            dependencies: ["AINotch"],
            path: "Tests/AINotchTests"
        )
    ]
)
