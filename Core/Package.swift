// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UllageCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "UllageCore", targets: ["UllageCore"])
    ],
    targets: [
        .target(name: "UllageCore"),
        .testTarget(
            name: "UllageCoreTests",
            dependencies: ["UllageCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
