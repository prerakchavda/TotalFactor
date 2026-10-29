// swift-tools-version: 5.10
import PackageDescription

/// Pure-Swift package target allowing `swift test` execution of all Total Factor core engines
/// (EMA Weight Trend, Adaptive Expenditure, Macro Targets & Carb Cycling, e1RM + Personal k-Curve,
/// Smart Progression, Plan Generator, Label OCR Parser, and Food Search Ranker) from macOS CLI or Xcode.
let package = Package(
    name: "TotalFactorCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "TotalFactorCore", targets: ["TotalFactorCore"])
    ],
    targets: [
        .target(
            name: "TotalFactorCore",
            path: "TotalFactor",
            exclude: [
                "App",
                "Models",
                "Services",
                "Intents",
                "Views",
                "Resources"
            ],
            sources: [
                "Core",
                "Engines"
            ]
        ),
        .testTarget(
            name: "TotalFactorTests",
            dependencies: ["TotalFactorCore"],
            path: "TotalFactorTests"
        )
    ]
)
