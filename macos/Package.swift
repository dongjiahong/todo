// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Navigator",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Navigator", targets: ["Navigator"])
    ],
    targets: [
        .systemLibrary(
            name: "CNavigatorCore",
            path: "Sources/CNavigatorCore"
        ),
        .executableTarget(
            name: "Navigator",
            dependencies: ["CNavigatorCore"],
            path: "Sources/Navigator",
            linkerSettings: [
                .unsafeFlags(["-L", "Lib", "-lnavigator_core"]),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security"),
                .linkedFramework("UserNotifications"),
                .linkedLibrary("resolv")
            ]
        )
    ]
)
