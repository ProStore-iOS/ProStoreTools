// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "ProStoreTools",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "ProStoreTools",
            targets: ["ProStoreTools"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", branch: "main"),
        .package(url: "https://github.com/khcrysalis/Zsign-Package.git", branch: "package")
    ],
    targets: [
        .target(
            name: "ProStoreTools",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "ZsignSwift", package: "ZsignPackage"),
            ],
            path: "Sources/ProStoreTools"
        ),
    ]
)
