// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexIsland",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexIsland", targets: ["CodexIsland"]),
        .executable(name: "codexisland", targets: ["CodexIslandCLI"]),
    ],
    targets: [
        .executableTarget(
            name: "CodexIsland",
            path: "Sources/CodexIsland"
        ),
        .executableTarget(
            name: "CodexIslandCLI",
            path: "Sources/CodexIslandCLI"
        ),
    ]
)
