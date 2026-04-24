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
        "Features/Outliner/120_OUTLINE_TEXT_TO_NODE_CONVERSION_PLAN_v2.md",
      ],
      resources: [
        .process("Assets.xcassets"),
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
