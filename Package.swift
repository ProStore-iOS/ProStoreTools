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
    targets: [
        .target(
            name: "ProStoreTools",
            path: "Sources/ProStoreTools"
        ),
    ]
)
