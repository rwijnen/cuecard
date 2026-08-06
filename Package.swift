// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Cuecard",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Cuecard",
            path: "Sources/Cuecard",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CuecardTests",
            dependencies: ["Cuecard"],
            path: "Tests/CuecardTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
