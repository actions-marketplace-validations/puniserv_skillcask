// swift-tools-version:6.0
import PackageDescription

// Every target builds in Swift 6 language mode (complete data-race checking) and spells out
// existential types; both are explicit so a future tools-version bump cannot loosen them.
let settings: [SwiftSetting] = [.swiftLanguageMode(.v6), .enableUpcomingFeature("ExistentialAny")]

let package = Package(
    name: "Skillcask",
    platforms: [.macOS(.v14)],
    targets: [
        // Drives the `skillcask` binary: invocations, process runner, JSON documents, errors. No SwiftUI.
        .target(name: "SkillcaskCore", swiftSettings: settings),
        // What the interface thinks in: entries with one health each, snapshots, filters, reports. Pure functions.
        .target(name: "SkillcaskDomain", dependencies: ["SkillcaskCore"], swiftSettings: settings),
        // The app-update check of D51 without its views: how the app was installed, what the sidebar card shows,
        // when the daily check is due, what is remembered. Foundation only and no network code: the CLI asks.
        .target(name: "SkillcaskUpdates", dependencies: ["SkillcaskCore"], swiftSettings: settings),
        // Stores and views. The executable holds only `@main`, so this library is what the tests import.
        // `Fixtures/design/` holds the board sample data `DesignFixtures` decodes for previews and the render tool.
        .target(
            name: "SkillcaskUI",
            dependencies: ["SkillcaskCore", "SkillcaskDomain", "SkillcaskUpdates"],
            resources: [.copy("Fixtures/design")],
            swiftSettings: settings
        ),
        .executableTarget(name: "Skillcask", dependencies: ["SkillcaskUI"], swiftSettings: settings),
        // Renders the preview registry to PNG for the design gate; never bundled (`bundle.sh` copies `Skillcask` only).
        .executableTarget(name: "SkillcaskRender", dependencies: ["SkillcaskUI"], swiftSettings: settings),
        .testTarget(
            name: "SkillcaskCoreTests",
            dependencies: ["SkillcaskCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: settings
        ),
        .testTarget(name: "SkillcaskDomainTests", dependencies: ["SkillcaskDomain"], swiftSettings: settings),
        .testTarget(name: "SkillcaskUpdatesTests", dependencies: ["SkillcaskUpdates"], swiftSettings: settings),
        .testTarget(name: "SkillcaskUITests", dependencies: ["SkillcaskUI"], swiftSettings: settings),
    ]
)
