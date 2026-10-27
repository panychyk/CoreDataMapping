// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CoreDataMapping",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "CoreDataMapping", targets: ["CoreDataMapping"])
    ],
    targets: [
        .target(name: "CoreDataMapping"),
        .testTarget(
            name: "CoreDataMappingTests",
            dependencies: ["CoreDataMapping"],
            exclude: ["Resources/GraphModel.xcdatamodeld"],
            resources: [.copy("Resources/GraphModel.momd")]
        )
    ],
    swiftLanguageModes: [.v5]
)
