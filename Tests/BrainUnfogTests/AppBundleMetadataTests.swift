import XCTest
@testable import BrainUnfog

final class AppBundleMetadataTests: XCTestCase {
  func testUserVisibleBundleNameIsBrainUnfog() throws {
    let infoURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("import/BUF/Info.plist", isDirectory: false)
    let data = try Data(contentsOf: infoURL)
    let plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
    )

    XCTAssertEqual(plist["CFBundleName"], "Brain Unfog")
    XCTAssertEqual(plist["CFBundleDisplayName"], "Brain Unfog")
    XCTAssertEqual(plist["CFBundleExecutable"], "Brain Unfog")
    XCTAssertEqual(plist["CFBundleIdentifier"], "com.brainunfog.app")
  }
}
