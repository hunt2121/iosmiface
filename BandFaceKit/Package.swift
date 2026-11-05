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
        .library(name: "FaceCompiler", targets: ["FaceCompiler"]),
        .executable(name: "wfc", targets: ["wfc"]),
    ],
    targets: [
        .target(
            name: "BandFaceKit",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // Компілятор циферблатів (порт WatchfaceCompiler 0.9.8)
        .target(name: "FaceCompiler"),
        .executableTarget(name: "wfc", dependencies: ["FaceCompiler"]),
        .testTarget(
            name: "BandFaceKitTests",
            dependencies: ["BandFaceKit"]
        ),
        .testTarget(
            name: "FaceCompilerTests",
            dependencies: ["FaceCompiler"]
        ),
    ]
)
