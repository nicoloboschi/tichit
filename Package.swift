// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tichit",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tichit",
            path: "Sources/Tichit"
        ),
        // Renders the .icns artwork from the same Logo code the app draws with.
        .executableTarget(
            name: "IconGen",
            path: "Sources/IconGen",
            sources: ["main.swift", "Logo.swift"]
        )
    ]
)
