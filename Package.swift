// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "immich-probe",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "immich-probe")
    ]
)
