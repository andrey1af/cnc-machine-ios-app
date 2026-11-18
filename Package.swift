// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CNCAppChecks",
    platforms: [.macOS(.v13), .iOS(.v17)],
    targets: [
        .target(name: "CNCCore", path: "cncapp/Models"),
        .testTarget(name: "CNCCoreTests", dependencies: ["CNCCore"], path: "tests")
    ]
)
