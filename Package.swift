// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KlimaxUI",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "KlimaxUI",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/KlimaxUI",
            resources: [
                .process("Resources"),
            ]
        )
    ]
)
