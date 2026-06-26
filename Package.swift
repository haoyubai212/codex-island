// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexIsland",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexIslandApp", targets: ["CodexIslandApp"]),
        .executable(name: "codexisland", targets: ["CodexIslandCLI"]),
    ],
    targets: [
        .executableTarget(
            name: "CodexIslandApp",
            path: "Sources/CodexIsland",
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "CodexIslandCLI",
            path: "Sources/CodexIslandCLI"
        ),
    ]
)
