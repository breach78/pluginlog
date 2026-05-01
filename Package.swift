// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "brain-unfog",
  platforms: [
    .macOS(.v15),
  ],
  products: [
    .executable(
      name: "BrainUnfog",
      targets: ["BrainUnfog"]
    ),
  ],
  targets: [
    .executableTarget(
      name: "BrainUnfog",
      path: "import/BUF",
      exclude: [
        ".DS_Store",
        "BrainUnfog.entitlements",
        "Info.plist",
        "Resources/ObsidianHelperPlugin",
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
      name: "BrainUnfogTests",
      dependencies: ["BrainUnfog"],
      path: "Tests/BrainUnfogTests"
    ),
  ]
)
