// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "pluginlog-harness",
  platforms: [
    .macOS(.v15),
  ],
  products: [
    .executable(
      name: "BrainUnfogHarness",
      targets: ["BrainUnfogHarness"]
    ),
  ],
  targets: [
    .executableTarget(
      name: "BrainUnfogHarness",
      path: "import/BUF",
      exclude: [
        ".DS_Store",
        "BrainUnfogHarness.entitlements",
        "Info.plist",
      ],
      resources: [
        .process("Assets.xcassets"),
        .copy("Resources/LogseqHelperPlugin"),
        .copy("Resources/ObsidianHelperPlugin"),
      ],
      linkerSettings: [
        .linkedLibrary("sqlite3"),
        .unsafeFlags([
          "-Xlinker", "-sectcreate",
          "-Xlinker", "__TEXT",
          "-Xlinker", "__info_plist",
          "-Xlinker", "import/BUF/Info.plist",
        ]),
      ]
    ),
    .testTarget(
      name: "BrainUnfogHarnessTests",
      dependencies: ["BrainUnfogHarness"],
      path: "Tests/BrainUnfogHarnessTests"
    ),
  ]
)
