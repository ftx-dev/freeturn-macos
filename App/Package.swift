// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FreeTurn",
    defaultLocalization: "ru",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FreeTurnKit"),
        .testTarget(name: "FreeTurnKitTests", dependencies: ["FreeTurnKit"]),
    ]
)
