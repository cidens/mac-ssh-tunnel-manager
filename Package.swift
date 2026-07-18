// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ssh-tunnel-manager",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SSHTunnelCore", targets: ["SSHTunnelCore"]),
        .executable(name: "ssh-tunnel-manager", targets: ["SSHTunnelManagerApp"])
    ],
    targets: [
        .target(
            name: "SSHTunnelCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "SSHTunnelManagerApp",
            dependencies: ["SSHTunnelCore"],
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "SSHTunnelCoreTests",
            dependencies: ["SSHTunnelCore"]
        ),
        .testTarget(
            name: "SSHTunnelManagerAppTests",
            dependencies: ["SSHTunnelManagerApp"]
        )
    ]
)
