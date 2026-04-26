import Foundation
import XCTest
@testable import BrainUnfog

final class ObsidianVaultPreferenceResolverTests: XCTestCase {
  func testUsesBookmarkWhenStoredPathMatchesBookmark() {
    let storedPath = "/tmp/obsidian-vault"
    let bookmarkURL = URL(fileURLWithPath: storedPath, isDirectory: true)

    let resolution = ObsidianVaultPreferenceResolver.resolve(
      storedPath: storedPath,
      bookmarkData: Data("bookmark".utf8),
      resolveBookmark: { _ in bookmarkURL }
    )

    XCTAssertEqual(resolution?.url, bookmarkURL.standardizedFileURL)
    XCTAssertEqual(resolution?.source, .bookmark)
    XCTAssertEqual(resolution?.didPreferStoredPathOverBookmark, false)
  }

  func testPrefersStoredPathWhenBookmarkPointsAtDifferentVault() {
    let storedPath = "/tmp/current-obsidian-vault"
    let staleBookmarkURL = URL(fileURLWithPath: "/tmp/old-obsidian-vault", isDirectory: true)

    let resolution = ObsidianVaultPreferenceResolver.resolve(
      storedPath: storedPath,
      bookmarkData: Data("bookmark".utf8),
      resolveBookmark: { _ in staleBookmarkURL }
    )

    XCTAssertEqual(
      resolution?.url,
      URL(fileURLWithPath: storedPath, isDirectory: true).standardizedFileURL
    )
    XCTAssertEqual(resolution?.source, .storedPath)
    XCTAssertEqual(resolution?.didPreferStoredPathOverBookmark, true)
  }

  func testFallsBackToStoredPathWhenBookmarkCannotResolve() {
    let storedPath = "/tmp/current-obsidian-vault"

    let resolution = ObsidianVaultPreferenceResolver.resolve(
      storedPath: storedPath,
      bookmarkData: Data("broken".utf8),
      resolveBookmark: { _ in throw CocoaError(.fileReadCorruptFile) }
    )

    XCTAssertEqual(
      resolution?.url,
      URL(fileURLWithPath: storedPath, isDirectory: true).standardizedFileURL
    )
    XCTAssertEqual(resolution?.source, .storedPath)
    XCTAssertEqual(resolution?.didPreferStoredPathOverBookmark, false)
  }

  func testUsesBookmarkWhenNoStoredPathExists() {
    let bookmarkURL = URL(fileURLWithPath: "/tmp/bookmarked-obsidian-vault", isDirectory: true)

    let resolution = ObsidianVaultPreferenceResolver.resolve(
      storedPath: nil,
      bookmarkData: Data("bookmark".utf8),
      resolveBookmark: { _ in bookmarkURL }
    )

    XCTAssertEqual(resolution?.url, bookmarkURL.standardizedFileURL)
    XCTAssertEqual(resolution?.source, .bookmark)
    XCTAssertEqual(resolution?.didPreferStoredPathOverBookmark, false)
  }

  func testReturnsNilWhenNeitherStoredPathNorBookmarkCanResolve() {
    let resolution = ObsidianVaultPreferenceResolver.resolve(
      storedPath: "  ",
      bookmarkData: Data("broken".utf8),
      resolveBookmark: { _ in throw CocoaError(.fileReadCorruptFile) }
    )

    XCTAssertNil(resolution)
  }
}
