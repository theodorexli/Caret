// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Caret",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Caret", targets: ["Caret"]),
        .library(name: "CaretCore", targets: ["CaretCore"]),
    ],
    dependencies: [
        .package(path: "../../packages/keytype/Packages/CompletionUI"),
    ],
    targets: [
        // Transport to the Python core plus focused-field capture. Separate
        // from the app target so the protocol logic is testable without a
        // running AppKit application.
        .target(
            name: "CaretCore",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "Caret",
            dependencies: ["CaretCore", .product(name: "CompletionUI", package: "CompletionUI")],
            exclude: ["Info.plist", "Assets.xcassets"],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(
            name: "CaretTests",
            dependencies: ["Caret"],
            path: "Tests",
            // The core's own tests live in their own target below.
            exclude: ["CaretCoreTests"]
        ),
        .testTarget(
            name: "CaretCoreTests",
            dependencies: ["CaretCore"],
            path: "Tests/CaretCoreTests"
        ),
    ]
)
