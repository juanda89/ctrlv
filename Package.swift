// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "InstantTranslator",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ControlVCore", targets: ["ControlVCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.11.0"),
    ],
    targets: [
        .target(
            name: "ControlVCore",
            dependencies: [],
            path: "Sources/ControlVCore"
        ),
        .executableTarget(
            name: "InstantTranslator",
            dependencies: [
                "ControlVCore",
                "HotKey",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "TelemetryDeck", package: "SwiftSDK"),
            ],
            path: "Sources/InstantTranslator"
        ),
        .testTarget(
            name: "InstantTranslatorTests",
            dependencies: ["InstantTranslator", "ControlVCore"],
            path: "Tests/InstantTranslatorTests"
        ),
    ]
)
