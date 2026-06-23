// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PanelID",
    platforms: [.macOS(.v13)],
    products: [
        // CLI binary is `panelid`; GUI executable is `PanelIDApp` (lives inside PanelID.app).
        // The two product names must differ by more than case — macOS APFS is case-insensitive,
        // so `panelid` and `PanelID` would collide as output binaries.
        .executable(name: "panelid", targets: ["panelid"]),
        .executable(name: "PanelIDApp", targets: ["PanelIDApp"]),
        .library(name: "PanelKit", targets: ["PanelKit"]),
    ],
    targets: [
        .target(name: "PanelKit"),
        .target(name: "PanelIO", dependencies: ["PanelKit"]),
        .executableTarget(name: "panelid", dependencies: ["PanelKit", "PanelIO"]),
        .executableTarget(name: "PanelIDApp", dependencies: ["PanelKit", "PanelIO"]),
        // Dependency-free test harness (Command Line Tools have no XCTest / Testing module).
        // Run with `swift run paneltests`. Not a product, so release builds skip it.
        .executableTarget(name: "paneltests", dependencies: ["PanelKit"]),
    ],
    swiftLanguageModes: [.v5]
)
