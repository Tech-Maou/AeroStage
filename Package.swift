// swift-tools-version: 6.0
import PackageDescription

// The app binary is called "AeroStageApp" because "AeroStage" and "aerostage" (CLI) would
// collide in the same build folder on case-insensitive APFS. scripts/bundle.sh renames it
// back to "AeroStage" inside the .app bundle.
let package = Package(
    name: "AeroStage",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AeroStageApp", targets: ["AeroStageApp"]),
        .executable(name: "aerostage", targets: ["aerostage"]),
    ],
    targets: [
        .target(name: "AeroStageCore"),
        .executableTarget(name: "AeroStageApp", dependencies: ["AeroStageCore"]),
        .executableTarget(name: "aerostage", dependencies: ["AeroStageCore"]),
        .testTarget(name: "AeroStageCoreTests", dependencies: ["AeroStageCore"]),
    ]
)
