// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "MilkteaLlamaKokoro",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(name: "MilkteaLlamaKokoro", targets: ["MilkteaLlamaKokoro"]),
    ],
    targets: [
        .systemLibrary(
            name: "Cllama",
            pkgConfig: "llama"
        ),
        .target(
            name: "MilkteaLlamaKokoro",
            dependencies: ["Cllama"]
        )
    ]
)
