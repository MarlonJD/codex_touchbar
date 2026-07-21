// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexTouchBar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "CodexTouchBar", targets: ["CodexTouchBar"]),
        .library(name: "CodexTouchBarCore", targets: ["CodexTouchBarCore"]),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .target(
            name: "CodexTouchBarCore",
            dependencies: ["CSQLite"],
            path: "Sources/CodexTouchBarCore"
        ),
        .target(
            name: "PrivateTouchBar",
            path: "Sources/PrivateTouchBar",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "CodexTouchBar",
            dependencies: [
                "CodexTouchBarCore",
                "PrivateTouchBar",
            ],
            path: "Sources/CodexTouchBar",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(
            name: "CodexTouchBarCoreTests",
            dependencies: ["CodexTouchBarCore", "CSQLite"],
            path: "Tests/CodexTouchBarCoreTests"
        ),
    ]
)
