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
            exclude: ["Resources/TestModel.xcdatamodeld"],
            resources: [.copy("Resources/TestModel.momd")]
        )
    ],
    swiftLanguageModes: [.v5]
)
