// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapacitorNodejs",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "CapacitorNodejs",
            targets: ["CapacitorNodejsSwift"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", exact: "8.1.0")
    ],
    targets: [
        // Binary target for the vendored NodeMobile.xcframework
        .binaryTarget(
            name: "NodeMobile",
            path: "ios/libnode/NodeMobile.xcframework"
        ),
        // ObjC++/C++ bridge layer (NodeProcess.mm, bridge.cpp)
        .target(
            name: "CapacitorNodejsBridge",
            dependencies: ["NodeMobile"],
            path: "ios/Bridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../libnode/include/node/"),
                .define("NODE_WANT_INTERNALS", to: "0"),
                .unsafeFlags(["-std=c++17"])
            ],
            linkerSettings: [
                .linkedFramework("Foundation")
            ]
        ),
        // Swift plugin layer (NodeJS.swift, NodeJSPlugin.swift)
        .target(
            name: "CapacitorNodejsSwift",
            dependencies: [
                "CapacitorNodejsBridge",
                "NodeMobile",
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Swift"
        )
    ]
)
