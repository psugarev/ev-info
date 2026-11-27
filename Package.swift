// swift-tools-version: 5.9
import PackageDescription

// SPM package = core logic library + tests.
// The iOS app itself is built from IoniqDrive.xcodeproj (App target),
// which compiles ALL sources directly (including the @main entry point).
// IoniqDriveApp.swift is therefore EXCLUDED here — a library target cannot contain @main.

let package = Package(
    name: "IoniqDrive",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "IoniqDriveCore", targets: ["IoniqDriveCore"])
    ],
    targets: [
        .target(
            name: "IoniqDriveCore",
            path: "Sources",
            exclude: [
                "App/IoniqDriveApp.swift",   // @main — belongs to the Xcode App target
                "CarPlay/README.md"
            ]
        ),
        .testTarget(
            name: "IoniqDriveCoreTests",
            dependencies: ["IoniqDriveCore"],
            path: "Tests"
        )
    ]
)
