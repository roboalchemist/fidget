// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Fidget",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "Fidget", targets: ["Fidget"]),
    ],
    targets: [
        .executableTarget(
            name: "Fidget",
            path: "Sources/Fidget"
        ),
    ]
)
