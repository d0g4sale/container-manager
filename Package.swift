// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ContainerUI",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.13.0")
    ],
    targets: [
        .executableTarget(
            name: "ContainerUI",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/ContainerUI",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                // Marks the SwiftPM build so resource loading can use
                // `Bundle.module` (SwiftPM-only) while the Xcode app target
                // falls back to `Bundle.main`. See DashboardView `appLogo`.
                .define("SWIFTPM_BUILD")
            ]
        )
    ]
)
