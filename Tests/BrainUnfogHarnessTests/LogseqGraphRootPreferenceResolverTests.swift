import Foundation
import XCTest
@testable import BrainUnfogHarness

final class LogseqGraphRootPreferenceResolverTests: XCTestCase {
  func testUsesBookmarkWhenStoredPathMatchesBookmark() throws {
    let storedPath = "/tmp/logseq-graph"
    let bookmarkURL = URL(fileURLWithPath: storedPath, isDirectory: true)

    let resolution = LogseqGraphRootPreferenceResolver.resolve(
      storedPath: storedPath,
      bookmarkData: Data("bookmark".utf8),
      resolveBookmark: { _ in bookmarkURL }
    )

    XCTAssertEqual(resolution?.url, bookmarkURL.standardizedFileURL)
    XCTAssertEqual(resolution?.source, .bookmark)
    XCTAssertEqual(resolution?.didPreferStoredPathOverBookmark, false)
  }

  func testPrefersStoredPathWhenBookmarkPointsAtDifferentGraph() throws {
    let storedPath = "/tmp/current-logseq-graph"
    let staleBookmarkURL = URL(fileURLWithPath: "/tmp/old-logseq-graph", isDirectory: true)

    let resolution = LogseqGraphRootPreferenceResolver.resolve(
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

  func testFallsBackToStoredPathWhenBookmarkCannotResolve() throws {
    let storedPath = "/tmp/current-logseq-graph"

    let resolution = LogseqGraphRootPreferenceResolver.resolve(
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

  func testUsesBookmarkWhenNoStoredPathExists() throws {
    let bookmarkURL = URL(fileURLWithPath: "/tmp/bookmarked-logseq-graph", isDirectory: true)

    let resolution = LogseqGraphRootPreferenceResolver.resolve(
      storedPath: nil,
      bookmarkData: Data("bookmark".utf8),
      resolveBookmark: { _ in bookmarkURL }
    )

    XCTAssertEqual(resolution?.url, bookmarkURL.standardizedFileURL)
    XCTAssertEqual(resolution?.source, .bookmark)
    XCTAssertEqual(resolution?.didPreferStoredPathOverBookmark, false)
  }

  func testReturnsNilWhenNeitherStoredPathNorBookmarkCanResolve() throws {
    let resolution = LogseqGraphRootPreferenceResolver.resolve(
      storedPath: "  ",
      bookmarkData: Data("broken".utf8),
      resolveBookmark: { _ in throw CocoaError(.fileReadCorruptFile) }
    )

    XCTAssertNil(resolution)
  }
}
