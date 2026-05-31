// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StepLang",
    products: [
        .library(name: "StepLang", targets: ["StepLang"])
    ],
    targets: [
        .target(name: "StepLang"),
        .testTarget(name: "StepLangTests", dependencies: ["StepLang"])
    ]
)
