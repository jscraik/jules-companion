// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Jules",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "JulesLib", targets: ["JulesLib"])
    ],
    dependencies: [
        .package(url: "https://github.com/CodeEditApp/CodeEditLanguages.git", branch: "main"),
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter.git", from: "0.8.0"),
        .package(url: "https://github.com/ra1028/DifferenceKit.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.3.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),
        .package(url: "https://github.com/soffes/HotKey", branch: "main"),
        .package(url: "https://github.com/kelly/devicons-swift", branch: "main"),
        .package(url: "https://github.com/airbnb/lottie-ios", from: "4.5.2"),
        .package(url: "https://github.com/ibrahimcetin/SwiftGitX", from: "0.4.0"),
        .package(url: "https://github.com/ibrahimcetin/libgit2.git", from: "1.9.2"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.5.0")
    ],
    targets: [
        .target(
            name: "JulesLib",
            dependencies: [
                .product(name: "CodeEditLanguages", package: "CodeEditLanguages"),
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "DifferenceKit", package: "DifferenceKit"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "HotKey", package: "HotKey"),
                .product(name: "Devicon", package: "devicons-swift"),
                .product(name: "Lottie", package: "lottie-ios"),
                .product(name: "SwiftGitX", package: "SwiftGitX"),
                .product(name: "libgit2", package: "libgit2"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "jules",
            exclude: [
                "julesApp.swift",
                "Assets.xcassets",
                "Info.plist"
            ]
        )
    ]
)
