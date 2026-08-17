// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "NetCollect",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NetCollectCore",
            targets: ["NetCollectCore"]
        ),
        .executable(
            name: "NetCollect",
            targets: ["NetCollect"]
        ),
        .executable(
            name: "NetCollectTests",
            targets: ["NetCollectTests"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NetCollectCore",
            dependencies: [],
            path: "Sources/NetCollectCore",
            cSettings: [
                .define("_DARWIN_C_SOURCE")
            ]
        ),
        .executableTarget(
            name: "NetCollect",
            dependencies: ["NetCollectCore"],
            path: "Sources/NetCollect"
        ),
        .executableTarget(
            name: "NetCollectTests",
            dependencies: ["NetCollectCore"],
            path: "Tests/NetCollectTests"
        ),
    ]
)
