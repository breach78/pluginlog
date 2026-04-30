import XCTest
@testable import BrainUnfog

@MainActor
final class AppUITestRuntimeTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func tearDown() async throws {
    TaskIdentityBridgeStore.reset()
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testConfigurationIsDisabledWithoutFlag() {
    XCTAssertNil(AppUITestRuntime.Configuration(environment: [:]))
  }

  func testConfigurationResolvesIsolatedRootFromEnvironment() throws {
    let root = try makeTemporaryDirectory(prefix: "BrainUnfogUITestRuntime")

    let configuration = try XCTUnwrap(
      AppUITestRuntime.Configuration(environment: [
        "BRAIN_UNFOG_UI_TEST_MODE": "1",
        "BRAIN_UNFOG_UI_TEST_ROOT": root.path,
      ])
    )

    XCTAssertEqual(configuration.rootURL.path, root.path)
    XCTAssertEqual(configuration.vaultRootURL.path, root.appendingPathComponent("vault").path)
    XCTAssertEqual(configuration.containerRootURL.path, root.appendingPathComponent("container").path)
  }

  func testConfigurationCanBeEnabledFromLaunchArguments() throws {
    let root = try makeTemporaryDirectory(prefix: "BrainUnfogUITestRuntimeArgs")

    let configuration = try XCTUnwrap(
      AppUITestRuntime.Configuration(
        environment: [:],
        arguments: [
          "Brain Unfog",
          AppUITestRuntime.modeArgument,
          AppUITestRuntime.rootArgument,
          root.path,
          AppUITestRuntime.resetArgument,
        ]
      )
    )

    XCTAssertEqual(configuration.rootURL.path, root.path)
    XCTAssertTrue(configuration.shouldReset)
  }

  func testPrepareCreatesSeedVaultAndBridgeRecordsWithoutRealReminders() async throws {
    let root = try makeTemporaryDirectory(prefix: "BrainUnfogUITestRuntime")
    let configuration = try XCTUnwrap(
      AppUITestRuntime.Configuration(environment: [
        "BRAIN_UNFOG_UI_TEST_MODE": "1",
        "BRAIN_UNFOG_UI_TEST_ROOT": root.path,
      ])
    )
    let storageCoordinator = LocalStorageCoordinator()
    let provider = UITestReminderProjectProvider(seed: configuration.seed)

    try await AppUITestRuntime.prepare(
      configuration: configuration,
      storageCoordinator: storageCoordinator,
      reminderProjectProvider: provider
    )

    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: configuration.vaultRootURL.appendingPathComponent("raw/projects").path
      )
    )
    XCTAssertEqual(storageCoordinator.paths?.root.path, configuration.containerRootURL.path)
    XCTAssertEqual(TaskIdentityBridgeStore.projectRecords().map(\.title).sorted(), [
      "UI 테스트 리스트",
      "일정 테스트 리스트",
    ])
    XCTAssertEqual(TaskIdentityBridgeStore.projectIDs().count, 2)
    XCTAssertEqual(provider.createdTaskCount, 0)
    let projectTitles = try await provider.fetchProjectListsInCurrentOrder().map(\.title)
    XCTAssertEqual(projectTitles, [
      "UI 테스트 리스트",
      "일정 테스트 리스트",
    ])
  }

  func testAppStateLaunchUsesUITestRuntimeWhenEnvironmentFlagIsEnabled() async throws {
    let root = try makeTemporaryDirectory(prefix: "BrainUnfogAppStateUITestRuntime")
    setenv(AppUITestRuntime.modeEnvironmentKey, "1", 1)
    setenv(AppUITestRuntime.rootEnvironmentKey, root.path, 1)
    setenv(AppUITestRuntime.resetEnvironmentKey, "1", 1)
    defer {
      unsetenv(AppUITestRuntime.modeEnvironmentKey)
      unsetenv(AppUITestRuntime.rootEnvironmentKey)
      unsetenv(AppUITestRuntime.resetEnvironmentKey)
    }

    let appState = AppState()

    await appState.launch()

    XCTAssertTrue(appState.reminderProjectProvider is UITestReminderProjectProvider)
    XCTAssertNotNil(appState.modelContainer)
    XCTAssertTrue(appState.boardsLoaded)
    XCTAssertEqual(appState.syncStatus, "UI Test Ready")
    XCTAssertEqual(appState.obsidianVaultRootURL?.path, root.appendingPathComponent("vault").path)
    XCTAssertEqual(appState.containerRootURL?.path, root.appendingPathComponent("container").path)
  }

  private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    temporaryRoots.append(root)
    return root
  }
}
