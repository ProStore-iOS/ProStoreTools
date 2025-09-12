import PackageDescription

let package = Package(
    name: "ProSourceManager",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "ProSourceManager",
            targets: ["ProSourceManager"]
        ),
    ],
    targets: [
        .target(
            name: "ProSourceManager",
            path: "Sources/ProSourceManager"
        ),
    ]
)
