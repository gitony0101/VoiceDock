// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VoiceDock",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VoiceDockCore",
            targets: ["VoiceDockCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "3f6b0553188a921f635df54b5e20442001037336"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.31.4")
    ],
    targets: [
        .target(
            name: "VoiceDockCore",
            dependencies: [
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLX", package: "mlx-swift")
            ],
            path: "VoiceDockCore/Sources"),
        .testTarget(
            name: "VoiceDockCoreTests",
            dependencies: ["VoiceDockCore"],
            path: "VoiceDockAppTests",
            exclude: [
                "AppDelegateIsolationTests.swift",
                "HotKeyManagerTests.swift",
                "PermissionManagerTests.swift"
            ])
    ]
)
