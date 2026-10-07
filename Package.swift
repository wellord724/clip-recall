// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipboardApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClipboardApp", targets: ["ClipboardApp"])
    ],
    targets: [
        .executableTarget(
            name: "ClipboardApp",
            path: "Sources/ClipboardApp"
        ),
        .testTarget(
            name: "ClipboardAppTests",
            dependencies: ["ClipboardApp"],
            path: "Tests/ClipboardAppTests"
        )
    ]
)
