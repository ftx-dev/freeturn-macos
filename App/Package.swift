// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FreeTurn",
    defaultLocalization: "ru",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FreeTurnKit"),
        .executableTarget(name: "FreeTurn", dependencies: ["FreeTurnKit"], resources: [.process("Resources")]),
        .executableTarget(name: "ftctl", dependencies: ["FreeTurnKit"]),
        .testTarget(name: "FreeTurnKitTests", dependencies: ["FreeTurnKit"]),
    ]
)
