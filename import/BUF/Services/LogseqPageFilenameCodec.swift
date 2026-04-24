import Foundation

enum LogseqPageFilenameFormat: Equatable, Sendable {
  case legacy
  case tripleLowbar
}

struct LogseqPageFilenameCodec: Equatable, Sendable {
  let format: LogseqPageFilenameFormat

  init(format: LogseqPageFilenameFormat) {
    self.format = format
  }

  init(graphRootURL: URL, fileManager: FileManager = .default) {
    self.format = Self.detectFormat(graphRootURL: graphRootURL, fileManager: fileManager)
  }

  static func filename(
    for pageTitle: String,
    format: LogseqPageFilenameFormat
  ) -> String {
    LogseqPageFilenameCodec(format: format).filenameStem(for: pageTitle) + ".md"
  }

  static func possibleTitles(forFileNamed fileName: String) -> Set<String> {
    let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    guard !stem.isEmpty else { return [] }

    var titles: Set<String> = []
    let legacyTitle = stem.removingPercentEncoding ?? stem
    if !legacyTitle.isEmpty {
      titles.insert(legacyTitle)
    }

    let tripleStem = stem.replacingOccurrences(of: "___", with: "/")
    let tripleTitle = tripleStem.removingPercentEncoding ?? tripleStem
    if !tripleTitle.isEmpty {
      titles.insert(tripleTitle)
    }

    return titles
  }

  func filenameStem(for pageTitle: String) -> String {
    let trimmedTitle = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return "Untitled" }

    switch format {
    case .legacy:
      return percentEncodedFilenameComponent(trimmedTitle)
    case .tripleLowbar:
      return percentEncodedFilenameComponent(
        trimmedTitle.replacingOccurrences(of: "/", with: "___")
      )
    }
  }

  func fileURL(in pagesRootURL: URL, for pageTitle: String) -> URL {
    pagesRootURL
      .appendingPathComponent(filenameStem(for: pageTitle), isDirectory: false)
      .appendingPathExtension("md")
  }

  func requiresExplicitTitleProperty(pageTitle: String) -> Bool {
    filenameStem(for: pageTitle) != pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func percentEncodedFilenameComponent(_ rawValue: String) -> String {
    let data = Data(rawValue.utf8)
    var encoded = ""
    encoded.reserveCapacity(data.count)

    for byte in data {
      if Self.allowedFilenameBytes.contains(byte) {
        encoded.append(Character(UnicodeScalar(byte)))
      } else {
        encoded.append(contentsOf: String(format: "%%%02X", byte))
      }
    }

    return encoded
  }

  private static func detectFormat(
    graphRootURL: URL,
    fileManager: FileManager
  ) -> LogseqPageFilenameFormat {
    let configURL = graphRootURL.appendingPathComponent("config.edn", isDirectory: false)
    guard fileManager.fileExists(atPath: configURL.path) else {
      return .legacy
    }

    guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
      return .legacy
    }

    if contents.contains(":file/name-format :legacy") {
      return .legacy
    }

    return .tripleLowbar
  }

  private static let allowedFilenameBytes: Set<UInt8> = Set(
    Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_().[]".utf8)
  )
}
