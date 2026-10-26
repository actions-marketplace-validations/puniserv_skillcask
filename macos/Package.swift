// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Skillcask",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SkillcaskCore"),
        .executableTarget(name: "Skillcask", dependencies: ["SkillcaskCore"]),
        .testTarget(name: "SkillcaskCoreTests", dependencies: ["SkillcaskCore"]),
    ]
)
