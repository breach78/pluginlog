import Foundation

actor GeminiGenerateContentSummaryService {
  static let shared = GeminiGenerateContentSummaryService()
  static let defaultModelName = "gemini-3.1-pro-preview"
  private static let minimumAcceptableSummaryLength = 24

  struct SummaryUsage: Codable, Hashable, Sendable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let thoughtsTokenCount: Int?
    let totalTokenCount: Int?
  }

  enum SummaryOutcome {
    case success(String, SummaryUsage?)
    case cancelled
    case failed
  }

  private let apiKeyStore = GeminiAPIKeyStore.shared
  private let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 45
    return URLSession(configuration: configuration)
  }()

  func summarize(
    prompt: String,
    model: String,
    temperature: Double = 1.0,
    maxOutputTokens: Int = 4096
  ) async -> SummaryOutcome {
    guard let apiKey = try? apiKeyStore.loadAPIKey(), !apiKey.isEmpty else {
      return .failed
    }

    let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedModel =
      trimmedModel.isEmpty ? Self.defaultModelName : trimmedModel

    guard
      let encodedModel = resolvedModel.addingPercentEncoding(
        withAllowedCharacters: .urlPathAllowed),
      let url = URL(
        string:
          "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent"
      )
    else {
      AppLogger.app.error("gemini summary request failed: invalid model path")
      return .failed
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

    do {
      request.httpBody = try JSONEncoder().encode(
        GeminiRequestBody(
          contents: [
            GeminiContent(
              parts: [
                GeminiPart(text: prompt)
              ]
            )
          ],
          generationConfig: GeminiGenerationConfig(
            temperature: temperature,
            maxOutputTokens: maxOutputTokens,
            thinkingConfig: GeminiThinkingConfig(thinkingLevel: "low")
          )
        )
      )

      let (data, response) = try await session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        return .failed
      }

      guard (200..<300).contains(httpResponse.statusCode) else {
        if let errorResponse = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data) {
          AppLogger.app.error(
            "gemini summary request failed: \(errorResponse.error.message, privacy: .public)"
          )
        } else {
          AppLogger.app.error(
            "gemini summary request failed with status \(httpResponse.statusCode, privacy: .public)"
          )
        }
        return .failed
      }

      let decoded = try JSONDecoder().decode(GeminiResponseBody.self, from: data)
      let usage = decoded.usageMetadata.map {
        SummaryUsage(
          promptTokenCount: $0.promptTokenCount,
          candidatesTokenCount: $0.candidatesTokenCount,
          thoughtsTokenCount: $0.thoughtsTokenCount,
          totalTokenCount: $0.totalTokenCount
        )
      }
      let text = decoded.candidates?
        .compactMap { candidate in
          candidate.content?.parts
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .first(where: { !$0.isEmpty })

      if let text, !text.isEmpty {
        if shouldRejectSummary(
          text,
          finishReason: decoded.candidates?.first?.finishReason
        ) {
          let finishReason = decoded.candidates?.first?.finishReason ?? "none"
          AppLogger.app.error(
            "gemini summary response rejected. finishReason=\(finishReason, privacy: .public) length=\(text.count, privacy: .public)"
          )
          return .failed
        }
        return .success(text, usage)
      }

      AppLogger.app.error("gemini summary response contained no readable text output")
      return .failed
    } catch is CancellationError {
      AppLogger.app.error("gemini summary request failed: cancelled")
      return .cancelled
    } catch let error as URLError where error.code == .cancelled {
      AppLogger.app.error("gemini summary request failed: cancelled")
      return .cancelled
    } catch {
      AppLogger.app.error(
        "gemini summary request failed: \(error.localizedDescription, privacy: .public)"
      )
      return .failed
    }
  }

  private func shouldRejectSummary(
    _ text: String,
    finishReason: String?
  ) -> Bool {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return true }

    if let finishReason {
      switch finishReason {
      case "STOP":
        break
      case "MAX_TOKENS":
        return true
      default:
        return true
      }
    }

    if normalized.count < Self.minimumAcceptableSummaryLength {
      return true
    }

    if normalized.range(of: #"[가-힣]"#, options: .regularExpression) == nil {
      return true
    }

    return false
  }
}

private struct GeminiRequestBody: Encodable {
  let contents: [GeminiContent]
  let generationConfig: GeminiGenerationConfig

  enum CodingKeys: String, CodingKey {
    case contents
    case generationConfig = "generationConfig"
  }
}

private struct GeminiContent: Codable {
  let parts: [GeminiPart]
}

private struct GeminiPart: Codable {
  let text: String?
}

private struct GeminiGenerationConfig: Encodable {
  let temperature: Double
  let maxOutputTokens: Int
  let thinkingConfig: GeminiThinkingConfig

  enum CodingKeys: String, CodingKey {
    case temperature
    case maxOutputTokens = "maxOutputTokens"
    case thinkingConfig = "thinkingConfig"
  }
}

private struct GeminiThinkingConfig: Encodable {
  let thinkingLevel: String

  enum CodingKeys: String, CodingKey {
    case thinkingLevel = "thinkingLevel"
  }
}

private struct GeminiResponseBody: Decodable {
  let candidates: [GeminiCandidate]?
  let usageMetadata: GeminiUsageMetadata?
}

private struct GeminiCandidate: Decodable {
  let content: GeminiContent?
  let finishReason: String?
}

private struct GeminiUsageMetadata: Decodable {
  let promptTokenCount: Int?
  let candidatesTokenCount: Int?
  let thoughtsTokenCount: Int?
  let totalTokenCount: Int?
}

private struct GeminiErrorEnvelope: Decodable {
  let error: GeminiErrorBody
}

private struct GeminiErrorBody: Decodable {
  let message: String
}
