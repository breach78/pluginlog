import XCTest
@testable import BrainUnfog

final class ObsidianVaultLayoutTests: XCTestCase {
  func testPrepareCreatesOnlyBufAndRawProjects() throws {
    let vaultURL = try makeTemporaryDirectory(named: "ObsidianLayout")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let layout = ObsidianVaultLayout(vaultRootURL: vaultURL)
    try FileManager.default.createDirectory(
      at: layout.obsidianConfigURL,
      withIntermediateDirectories: true
    )

    try layout.prepareAppDirectories()

    XCTAssertTrue(FileManager.default.fileExists(atPath: layout.sidecarRootURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: layout.rawProjectsRootURL.path))
    var isDirectory: ObjCBool = false
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: layout.obsidianConfigURL.path,
        isDirectory: &isDirectory
      )
    )
    XCTAssertTrue(isDirectory.boolValue)
    for legacyDirectory in ["attachments", "history", "archive", "notes", "exports"] {
      XCTAssertFalse(
        FileManager.default.fileExists(
          atPath: layout.sidecarRootURL.appendingPathComponent(legacyDirectory).path
        )
      )
    }
  }

  func testCandidateStateDetectsExistingObsidianDirectoryWithoutCreatingIt() throws {
    let vaultURL = try makeTemporaryDirectory(named: "ObsidianLayoutCandidate")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let layout = ObsidianVaultLayout(vaultRootURL: vaultURL)

    XCTAssertEqual(layout.candidateState(), .candidateMissingObsidianDirectory)

    try FileManager.default.createDirectory(
      at: layout.obsidianConfigURL,
      withIntermediateDirectories: true
    )

    XCTAssertEqual(layout.candidateState(), .existingVault)
  }

  func testPrepareDoesNotDirtyCandidateFolderWithoutObsidianConfig() throws {
    let vaultURL = try makeTemporaryDirectory(named: "ObsidianLayoutCandidateReadOnly")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let layout = ObsidianVaultLayout(vaultRootURL: vaultURL)

    XCTAssertThrowsError(try layout.prepareAppDirectories()) { error in
      XCTAssertEqual(
        error as? ObsidianVaultLayout.LayoutError,
        .missingObsidianConfigDirectory(layout.obsidianConfigURL)
      )
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: layout.sidecarRootURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: layout.rawProjectsRootURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: layout.obsidianConfigURL.path))
  }

  func testCandidateStateDoesNotTreatObsidianFileAsExistingVault() throws {
    let vaultURL = try makeTemporaryDirectory(named: "ObsidianLayoutInvalidConfig")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let layout = ObsidianVaultLayout(vaultRootURL: vaultURL)
    try "not a directory".write(
      to: layout.obsidianConfigURL,
      atomically: true,
      encoding: .utf8
    )

    XCTAssertEqual(layout.candidateState(), .candidateMissingObsidianDirectory)
  }

  private func makeTemporaryDirectory(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
