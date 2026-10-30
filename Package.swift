// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StorageAtlas",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StorageAtlas", targets: ["StorageAtlas"]),
        .library(name: "StorageCore", targets: ["StorageCore"])
    ],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "StorageCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "StorageAtlas", dependencies: ["StorageCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "StorageCoreTests", dependencies: ["StorageCore"])
    ],
    swiftLanguageModes: [.v5]
)
