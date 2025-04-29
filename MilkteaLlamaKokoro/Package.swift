// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MilkteaLlamaKokoro",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "MilkteaLlamaKokoro",
            targets: ["MilkteaLlamaKokoro"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "SherpaOnnx",
            path: "Frameworks/sherpa-onnx.xcframework"
        ),
        .binaryTarget(
            name: "SherpaOnnxUtils",
            path: "Frameworks/onnxruntime.xcframework"
        ),
        .systemLibrary(
            name: "Cllama",
            pkgConfig: "llama"
        ),
        .target(
            name: "SherpaOnnxC",
            path: "Sources/SherpaOnnxC",
            publicHeadersPath: ".",
            cSettings: [
                    .headerSearchPath("sherpa-onnx/sherpa-onnx/c-api")
                ]
        ),
        .target(
            name: "MilkteaLlamaKokoro",
            dependencies: [
                "SherpaOnnx",
                "SherpaOnnxUtils",
                "SherpaOnnxC",
                "Cllama"
            ]
        )
    ]
)
