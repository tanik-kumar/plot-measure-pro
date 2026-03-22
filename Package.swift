// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PlotMeasurePro",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "PlotMeasurePro", targets: ["PlotMeasurePro"]),
    ],
    targets: [
        .executableTarget(
            name: "PlotMeasurePro",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreImage"),
                .linkedFramework("PDFKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Vision"),
            ]
        ),
        .testTarget(
            name: "PlotMeasureProTests",
            dependencies: ["PlotMeasurePro"]
        ),
    ]
)
