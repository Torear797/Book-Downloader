// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BookDownloader",
    platforms: [
        .macOS(.v13), .iOS(.v12), .tvOS(.v12), .watchOS(.v4), .visionOS(.v1)
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.0"))
    ],
    targets: [
        .executableTarget(
            name: "BookDownloader",
            dependencies: [
                .byName(name: "ZIPFoundation")
            ],
            path: "Book Downloader"
        ),
    ]
)
