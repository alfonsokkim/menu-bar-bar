// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tray",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tray", targets: ["Tray"])],
    targets: [
        .target(name: "TrayCore"),
        .executableTarget(name: "Tray", dependencies: ["TrayCore"], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "TrayCoreTests", dependencies: ["TrayCore"]),
        .testTarget(name: "TrayRenderingTests", dependencies: ["Tray"])
    ]
)
