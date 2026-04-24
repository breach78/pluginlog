import Foundation

enum LogseqDeepLinkingError: LocalizedError {
  case graphRootUnavailable
  case graphNameUnavailable
  case pageTitleUnavailable
  case invalidProjectPageURL

  var errorDescription: String? {
    switch self {
    case .graphRootUnavailable:
      return "Logseq 그래프 루트가 설정되지 않았습니다."
    case .graphNameUnavailable:
      return "Logseq 그래프 이름을 확인할 수 없습니다."
    case .pageTitleUnavailable:
      return "열 프로젝트 페이지 이름이 없습니다."
    case .invalidProjectPageURL:
      return "Logseq 페이지 링크를 만들지 못했습니다."
    }
  }
}

enum LogseqDeepLinking {
  static func projectPageURL(graphRootURL: URL?, pageTitle: String) throws -> URL {
    guard let graphRootURL else {
      throw LogseqDeepLinkingError.graphRootUnavailable
    }
    return try projectPageURL(graphRootURL: graphRootURL, pageTitle: pageTitle)
  }

  static func projectPageURL(graphRootURL: URL, pageTitle: String) throws -> URL {
    let graphName = graphRootURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !graphName.isEmpty else {
      throw LogseqDeepLinkingError.graphNameUnavailable
    }

    let resolvedPageTitle = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !resolvedPageTitle.isEmpty else {
      throw LogseqDeepLinkingError.pageTitleUnavailable
    }

    var components = URLComponents()
    components.scheme = "logseq"
    components.host = "graph"
    components.percentEncodedPath = "/" + encodedGraphName(graphName)
    components.queryItems = [URLQueryItem(name: "page", value: resolvedPageTitle)]

    guard let url = components.url else {
      throw LogseqDeepLinkingError.invalidProjectPageURL
    }
    return url
  }

  private static func encodedGraphName(_ graphName: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    return graphName.addingPercentEncoding(withAllowedCharacters: allowed) ?? graphName
  }
}

enum WorkspaceProjectSelectionRouting {
  enum Destination: String {
    case logseqPage
    case embeddedDetail
  }

  private static let threadDictionaryKey = "workspace.projectSelectionRouting.destination"

  static func perform(_ destination: Destination, action: () -> Void) {
    let threadDictionary = Thread.current.threadDictionary
    let previousRawValue = threadDictionary[threadDictionaryKey] as? String
    threadDictionary[threadDictionaryKey] = destination.rawValue
    action()
    if let previousRawValue {
      threadDictionary[threadDictionaryKey] = previousRawValue
    } else {
      threadDictionary.removeObject(forKey: threadDictionaryKey)
    }
  }

  static func consume(default defaultDestination: Destination = .logseqPage) -> Destination {
    let threadDictionary = Thread.current.threadDictionary
    let rawValue = threadDictionary[threadDictionaryKey] as? String
    threadDictionary.removeObject(forKey: threadDictionaryKey)
    return rawValue.flatMap(Destination.init(rawValue:)) ?? defaultDestination
  }
}

enum RetainedSurfaceMutationGate {
  enum Surface: String {
    case timeline
    case schedule
  }

  static func block(_ surface: Surface, feature: String) -> String {
    AppLogger.ui.error(
      "retained slice blocked \(surface.rawValue, privacy: .public) mutation [\(feature, privacy: .public)]"
    )

    switch surface {
    case .timeline:
      return "Timeline 편집은 V1a retained slice에서 비활성화되어 있습니다. 프로젝트는 Logseq에서 열고, 변경은 원본 경로에서 진행하세요."
    case .schedule:
      return "Schedule 편집은 V1a retained slice에서 비활성화되어 있습니다. 프로젝트는 Logseq에서 열고, 변경은 원본 경로에서 진행하세요."
    }
  }
}
