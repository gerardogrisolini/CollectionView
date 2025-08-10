// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CollectionView",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "CollectionView",
            targets: ["CollectionView"]
        ),
    ],
    targets: [
        .target(
            name: "CollectionView"
        ),
        .testTarget(
            name: "CollectionViewTests",
            dependencies: ["CollectionView"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
