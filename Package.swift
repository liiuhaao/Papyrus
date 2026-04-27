// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Papyrus",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PapyrusCore", targets: ["PapyrusCore"]),
        .executable(name: "Papyrus", targets: ["Papyrus"]),
        .executable(name: "PapyrusCLI", targets: ["PapyrusCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.3.1")
    ],
    targets: [
        .target(
            name: "PapyrusCore",
            dependencies: [
                .product(name: "Textual", package: "textual")
            ],
            path: "Sources/PapyrusCore",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "Papyrus",
            dependencies: [
                "PapyrusCore"
            ],
            path: "Sources/PapyrusApp",
            resources: [],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "PapyrusCLI",
            dependencies: [
                "PapyrusCore"
            ],
            path: "Sources/PapyrusCLI",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "PapyrusTests",
            dependencies: ["PapyrusCore"],
            path: "PapyrusTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
