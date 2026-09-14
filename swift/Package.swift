// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "envdoctor",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "EnvdoctorKit", targets: ["EnvdoctorKit"]),
        .executable(name: "envdoctor", targets: ["envdoctor"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
    ],
    targets: [
        .target(
            name: "EnvdoctorKit",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .target(name: "CZlib"),
            ],
            path: "Sources/EnvdoctorKit"
        ),
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .executableTarget(
            name: "envdoctor",
            dependencies: ["EnvdoctorKit"],
            path: "Sources/envdoctor"
        ),
        .testTarget(
            name: "envdoctorTests",
            dependencies: ["EnvdoctorKit"],
            path: "Tests/envdoctorTests"
        ),
    ]
)
