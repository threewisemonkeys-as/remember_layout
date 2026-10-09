// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Remember",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Remember", targets: ["Remember"])],
    targets: [
        .target(name: "LayoutCore"),
        .executableTarget(name: "Remember", dependencies: ["LayoutCore"]),
        .executableTarget(name: "LayoutCoreChecks", dependencies: ["LayoutCore"], path: "Tests/LayoutCoreTests")
    ]
)
