// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RemoteKit",
    platforms: [.macOS(.v26)],
    products: [
        // 核心功能，不含私有接口，两个版本共用
        .library(name: "RemoteKit", targets: ["RemoteKit"]),
        // 触控面读取，依赖私有框架 MultitouchSupport，仅官网版使用
        .library(name: "RemoteKitTouch", targets: ["RemoteKitTouch"]),
        // 执行 Shell 与 AppleScript，仅官网版使用
        .library(name: "RemoteKitScripts", targets: ["RemoteKitScripts"]),
    ],
    targets: [
        .target(
            name: "RemoteKit",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .target(
            name: "RemoteKitTouch",
            dependencies: ["RemoteKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .target(
            name: "RemoteKitScripts",
            dependencies: ["RemoteKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "RemoteKitTests",
            dependencies: ["RemoteKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
