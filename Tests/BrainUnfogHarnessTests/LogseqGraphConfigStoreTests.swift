import XCTest
@testable import BrainUnfogHarness

final class LogseqGraphConfigStoreTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func tearDown() async throws {
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testEnsureAddsInternalIdentityPropertiesToHiddenConfig() throws {
    let graphRoot = try makeGraphRoot()
    let configURL = try writeConfig(
      """
      {:meta/version 1
       :property-pages/enabled? true}
      """,
      graphRoot: graphRoot
    )

    try LogseqGraphConfigStore(graphRootURL: graphRoot).ensureInternalIdentityPropertiesHidden()

    let contents = try String(contentsOf: configURL, encoding: .utf8)
    XCTAssertTrue(contents.contains(":reminder_list_external_id"))
    XCTAssertTrue(contents.contains(":reminder-list-external-id"))
    XCTAssertTrue(contents.contains(":reminder_external_id"))
    XCTAssertTrue(contents.contains(":reminder-external-id"))

    let cssContents = try String(
      contentsOf: graphRoot.appendingPathComponent("logseq/custom.css", isDirectory: false),
      encoding: .utf8
    )
    XCTAssertTrue(cssContents.contains("Brain Unfog internal identity properties: begin"))
    XCTAssertTrue(cssContents.contains("a[data-ref=\"reminder_list_external_id\" i]"))
    XCTAssertTrue(cssContents.contains("a[data-ref=\"reminder-list-external-id\" i]"))
    XCTAssertTrue(cssContents.contains("a[data-ref=\"reminder_external_id\" i]"))
    XCTAssertTrue(cssContents.contains("a[data-ref=\"reminder-external-id\" i]"))
    XCTAssertTrue(cssContents.contains("Brain Unfog schedule chips"))
    XCTAssertTrue(cssContents.contains("Brain Unfog completed task filter"))
    XCTAssertTrue(cssContents.contains("div.ls-block:has(> div.flex.flex-row input[type=\"checkbox\"]:checked)"))
    XCTAssertTrue(cssContents.contains("div.ls-block:has(> div.flex.flex-row .block-content-inner .marker-switch.done)"))
    XCTAssertTrue(cssContents.contains("div.block-properties:not(.page-properties)"))
    XCTAssertTrue(cssContents.contains("a[data-ref=\"date\" i]"))
    XCTAssertTrue(cssContents.contains("a[data-ref=\"duration\" i]"))
    XCTAssertTrue(cssContents.contains("a[data-ref=\"repeat\" i]"))
    XCTAssertTrue(cssContents.contains("div.block-content:has(div.block-properties:not(.page-properties) a[data-ref=\"date\" i])"))
    XCTAssertTrue(cssContents.contains("div.block-content-wrapper:has(div.block-properties:not(.page-properties) a[data-ref=\"date\" i])"))
    XCTAssertTrue(cssContents.contains("div.flex.flex-col.block-content-wrapper:has(div.block-properties:not(.page-properties) a[data-ref=\"date\" i])"))
    XCTAssertTrue(cssContents.contains("div.block-content-wrapper > div.flex.flex-row > div.flex-1.w-full:has(> div.block-content div.block-properties:not(.page-properties) a[data-ref=\"date\" i])"))
    XCTAssertTrue(cssContents.contains("> div.block-content-inner > div.flex-1.w-full"))
    XCTAssertTrue(cssContents.contains("div.block-properties:not(.page-properties):has(a[data-ref=\"date\" i])"))
    XCTAssertFalse(cssContents.contains(":has(> div:has("))
    XCTAssertFalse(cssContents.contains(":has(div.block-properties:not(.page-properties) > div:has("))
    XCTAssertTrue(cssContents.contains("width: 100% !important;"))
    XCTAssertTrue(cssContents.contains("margin-left: auto !important;"))
    XCTAssertTrue(cssContents.contains("border: 0 !important;"))
    XCTAssertTrue(cssContents.contains("background: rgba(238, 240, 243, 0.92) !important;"))
    XCTAssertTrue(cssContents.contains("border-radius: 4px;"))
    XCTAssertFalse(cssContents.contains("border-radius: 999px;"))
    XCTAssertTrue(cssContents.contains("> div:has(a[data-ref=\"date\" i]) > div:first-child"))
    XCTAssertTrue(cssContents.contains("> div:has(a[data-ref=\"date\" i]) > span.mr-1"))
    XCTAssertTrue(cssContents.contains("> div:has(a[data-ref=\"date\" i]) > div.page-property-value"))
    XCTAssertTrue(cssContents.contains("> div:has(a[data-ref=\"date\" i]) a"))
    XCTAssertTrue(cssContents.contains("> div:has(a[data-ref=\"duration\" i]) a"))
    XCTAssertTrue(cssContents.contains("> div:has(a[data-ref=\"repeat\" i]) a"))
  }

  func testCompletedTaskFilterCanBeRemovedFromManagedCSS() throws {
    let originalCSS = LogseqGraphConfigStore.updatingCustomCSS("", hideCompletedTasks: true)
    let updatedCSS = LogseqGraphConfigStore.updatingCustomCSS(
      originalCSS,
      hideCompletedTasks: false
    )

    XCTAssertTrue(originalCSS.contains("Brain Unfog completed task filter"))
    XCTAssertFalse(updatedCSS.contains("Brain Unfog completed task filter"))
    XCTAssertFalse(updatedCSS.contains("input[type=\"checkbox\"]:checked"))
    XCTAssertTrue(updatedCSS.contains("Brain Unfog schedule chips"))
    XCTAssertEqual(
      updatedCSS.components(separatedBy: "Brain Unfog internal identity properties: begin").count - 1,
      1
    )
  }

  func testEnsureMergesExistingHiddenConfigWithoutDroppingUserProperties() throws {
    let graphRoot = try makeGraphRoot()
    let configURL = try writeConfig(
      """
      {:meta/version 1
       :block-hidden-properties #{:public :icon}
       :property-pages/excludelist #{:duration :author}}
      """,
      graphRoot: graphRoot
    )

    try LogseqGraphConfigStore(graphRootURL: graphRoot).ensureInternalIdentityPropertiesHidden()

    let contents = try String(contentsOf: configURL, encoding: .utf8)
    XCTAssertTrue(contents.contains(":public"))
    XCTAssertTrue(contents.contains(":icon"))
    XCTAssertTrue(contents.contains(":duration"))
    XCTAssertTrue(contents.contains(":author"))
    XCTAssertTrue(contents.contains(":reminder_list_external_id"))
    XCTAssertTrue(contents.contains(":reminder-list-external-id"))
  }

  func testEnsureIsIdempotent() throws {
    let graphRoot = try makeGraphRoot()
    let configURL = try writeConfig(
      """
      {:meta/version 1}
      """,
      graphRoot: graphRoot
    )
    let store = LogseqGraphConfigStore(graphRootURL: graphRoot)

    try store.ensureInternalIdentityPropertiesHidden()
    let once = try String(contentsOf: configURL, encoding: .utf8)
    let cssURL = graphRoot.appendingPathComponent("logseq/custom.css", isDirectory: false)
    let cssOnce = try String(contentsOf: cssURL, encoding: .utf8)
    try store.ensureInternalIdentityPropertiesHidden()
    let twice = try String(contentsOf: configURL, encoding: .utf8)
    let cssTwice = try String(contentsOf: cssURL, encoding: .utf8)

    XCTAssertEqual(once, twice)
    XCTAssertEqual(cssOnce, cssTwice)
  }

  func testEnsurePreservesExistingCustomCSS() throws {
    let graphRoot = try makeGraphRoot()
    _ = try writeConfig("{:meta/version 1}", graphRoot: graphRoot)
    let cssURL = graphRoot.appendingPathComponent("logseq/custom.css", isDirectory: false)
    try ".user-rule { color: red; }\n".write(to: cssURL, atomically: true, encoding: .utf8)

    try LogseqGraphConfigStore(graphRootURL: graphRoot).ensureInternalIdentityPropertiesHidden()

    let cssContents = try String(contentsOf: cssURL, encoding: .utf8)
    XCTAssertTrue(cssContents.contains(".user-rule { color: red; }"))
    XCTAssertEqual(
      cssContents.components(separatedBy: "Brain Unfog internal identity properties: begin").count - 1,
      1
    )
  }

  private func makeGraphRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("LogseqGraphConfigStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    temporaryRoots.append(root)
    return root
  }

  private func writeConfig(_ contents: String, graphRoot: URL) throws -> URL {
    let logseqURL = graphRoot.appendingPathComponent("logseq", isDirectory: true)
    try FileManager.default.createDirectory(at: logseqURL, withIntermediateDirectories: true)
    let configURL = logseqURL.appendingPathComponent("config.edn", isDirectory: false)
    try contents.write(to: configURL, atomically: true, encoding: .utf8)
    return configURL
  }
}
