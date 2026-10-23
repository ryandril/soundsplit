// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SoundSplit",
    platforms: [.macOS("14.4")],
    targets: [
        .executableTarget(name: "SoundSplit", path: "Sources/SoundSplit")
    ]
)
