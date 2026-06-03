// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CorpusGenerator",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CorpusKit", targets: ["CorpusKit"]),
        .executable(name: "corpus-gen", targets: ["CorpusGenerator"]),
    ],
    targets: [
        .target(name: "CorpusKit"),
        .target(name: "CorpusGenKit", dependencies: ["CorpusKit"]),
        .executableTarget(name: "CorpusGenerator", dependencies: ["CorpusGenKit", "CorpusKit"]),
        .testTarget(name: "CorpusKitTests", dependencies: ["CorpusKit"]),
        .testTarget(name: "CorpusGenKitTests", dependencies: ["CorpusGenKit", "CorpusKit"]),
    ]
)
