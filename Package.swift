// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "InstantTranslator",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "InstantTranslator",
            dependencies: [
                "HotKey",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/InstantTranslator"
        ),
        .testTarget(
            name: "InstantTranslatorTests",
            dependencies: ["InstantTranslator"],
            path: "Tests/InstantTranslatorTests"
        ),
    ]
)
