// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SolisSolarMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SolisSolarMonitor",
            path: "Sources/SolisSolarMonitor"
        )
    ]
)
