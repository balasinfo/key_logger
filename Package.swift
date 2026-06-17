// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ActivityTracker",
    platforms: [.macOS(.v12)],
    targets: [
        .target(
            name: "ActivityCore"
        ),
        .executableTarget(
            name: "activitytracker",
            dependencies: ["ActivityCore"]
        ),
        .testTarget(
            name: "ActivityCoreTests",
            dependencies: ["ActivityCore"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
