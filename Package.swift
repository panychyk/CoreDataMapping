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
            exclude: ["MedicalCongress/Resources/MedicalCongressModel.xcdatamodeld"],
            resources: [.copy("MedicalCongress/Resources/MedicalCongressModel.momd")]
        )
    ],
    swiftLanguageModes: [.v5]
)
