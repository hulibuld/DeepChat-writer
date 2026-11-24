// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeepChat",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "DeepChatCore", targets: ["DeepChatCore"]),
        .library(name: "DeepChatUI", targets: ["DeepChatUI"])
    ],
    targets: [
        .target(name: "DeepChatCore", path: "Sources/DeepChatCore"),
        .target(name: "DeepChatUI", dependencies: ["DeepChatCore"], path: "Sources/DeepChatUI")
    ]
)