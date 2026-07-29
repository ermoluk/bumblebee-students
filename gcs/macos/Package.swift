// swift-tools-version:5.9
import PackageDescription

// Native macOS app: a WKWebView shell that hosts the Bumblebee GCS frontend
// locally and connects to a drone selected from a network scan. No third-party
// dependencies on purpose — the Mac is usually on the drone's wifi hotspot with
// no internet, so SwiftPM cannot fetch remote packages.
let package = Package(
    name: "GCSApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GCSApp",
            path: "Sources/GCSApp",
            resources: [.process("Resources")]
        )
    ]
)
