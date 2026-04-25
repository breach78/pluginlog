import Foundation

struct ObsidianVaultPreferenceResolver {
  enum Source: Equatable {
    case storedPath
    case bookmark
  }

  struct Resolution: Equatable {
    let url: URL
    let source: Source
    let didPreferStoredPathOverBookmark: Bool
  }

  static func resolve(
    storedPath: String?,
    bookmarkData: Data?,
    resolveBookmark: (Data) throws -> URL
  ) -> Resolution? {
    let storedPathURL = normalizedStoredPathURL(storedPath)
    let bookmarkURL = bookmarkData.flatMap { data in try? resolveBookmark(data) }

    if let storedPathURL, let bookmarkURL {
      if sameFilePath(storedPathURL, bookmarkURL) {
        return Resolution(
          url: bookmarkURL,
          source: .bookmark,
          didPreferStoredPathOverBookmark: false
        )
      }
      return Resolution(
        url: storedPathURL,
        source: .storedPath,
        didPreferStoredPathOverBookmark: true
      )
    }

    if let storedPathURL {
      return Resolution(
        url: storedPathURL,
        source: .storedPath,
        didPreferStoredPathOverBookmark: false
      )
    }

    if let bookmarkURL {
      return Resolution(
        url: bookmarkURL,
        source: .bookmark,
        didPreferStoredPathOverBookmark: false
      )
    }

    return nil
  }

  private static func normalizedStoredPathURL(_ storedPath: String?) -> URL? {
    guard let storedPath else { return nil }
    let trimmed = storedPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return URL(fileURLWithPath: trimmed, isDirectory: true)
      .standardizedFileURL
  }

  private static func sameFilePath(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
  }
}
