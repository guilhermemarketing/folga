// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Folga",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "Folga",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Folga",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                                          "-Xlinker", "-rpath", "-Xlinker", "@executable_path"])]  // .app, bare swift build
        )
    ]
)
