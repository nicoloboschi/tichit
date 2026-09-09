// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tich",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tich",
            path: "Sources/Tich"
        )
    ]
)
