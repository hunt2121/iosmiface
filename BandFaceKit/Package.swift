// swift-tools-version:5.9
// SPDX-License-Identifier: MIT
import PackageDescription

let package = Package(
    name: "BandFaceKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "BandFaceKit", targets: ["BandFaceKit"]),
    ],
    targets: [
        .target(
            name: "BandFaceKit",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "BandFaceKitTests",
            dependencies: ["BandFaceKit"]
        ),
    ]
)
