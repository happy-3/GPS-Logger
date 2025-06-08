// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GPSLogger",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "GPS_Logger", targets: ["GPS_Logger"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.3.0")
    ],
    targets: [
        .target(
            name: "GPS_Logger",
            path: "GPS Logger",
            resources: [
                .process("Assets.xcassets"),
                .process("Preview Content"),
                .process("Airspace")
            ]
        ),
        .testTarget(
            name: "GPS_LoggerTests",
            dependencies: [
                "GPS_Logger",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "GPS LoggerTests"
        )
        // UI tests are not included in SPM
    ]
)
