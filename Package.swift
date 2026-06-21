// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VoiceDock",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "VoiceDock",
            targets: ["VoiceDockApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "VoiceDockApp",
            dependencies: [
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift")
            ],
            path: "VoiceDockApp"),
        .testTarget(
            name: "VoiceDockAppTests",
            dependencies: ["VoiceDockApp"],
            path: "VoiceDockAppTests")
    ]
)