// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Caret",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Caret", targets: ["Caret"])],
    targets: [
        .executableTarget(
            name: "Caret",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
            ]
        ),
    ]
)
