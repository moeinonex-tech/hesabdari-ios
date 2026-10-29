// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HesabCore",
    defaultLocalization: "fa",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "HesabCore", targets: ["HesabCore"])
    ],
    targets: [
        .target(name: "HesabCore"),
        .testTarget(
            name: "HesabCoreTests",
            dependencies: ["HesabCore"],
            resources: [.copy("Goldens")]
        )
    ],
    swiftLanguageModes: [.v5]
)
