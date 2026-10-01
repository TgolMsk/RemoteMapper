// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RemoteKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "RemoteKit", targets: ["RemoteKit"]),
    ],
    targets: [
        .target(
            name: "RemoteKit",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "RemoteKitTests",
            dependencies: ["RemoteKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
