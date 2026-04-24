import Foundation

actor OpenAIResponsesSummaryService {
  static let shared = OpenAIResponsesSummaryService()
  static let modelName = "gpt-5-nano"

  private let apiURL: URL = {
    guard let url = URL(string: "https://api.openai.com/v1/responses") else {
      preconditionFailure("OpenAI responses URL must be valid")
    }
    return url
  }()
  private let apiKeyStore = OpenAIAPIKeyStore.shared
  private let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 45
    return URLSession(configuration: configuration)
  }()

  func summarize(prompt: String) async -> String? {
    guard let apiKey = try? apiKeyStore.loadAPIKey(), !apiKey.isEmpty else {
      return nil
    }

    var request = URLRequest(url: apiURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    do {
      request.httpBody = try JSONEncoder().encode(
        RequestBody(
          model: Self.modelName,
          input: prompt,
          maxOutputTokens: 220
        )
      )

      let (data, response) = try await session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        return nil
      }

      guard (200..<300).contains(httpResponse.statusCode) else {
        if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
          AppLogger.app.error(
            "openai summary request failed: \(errorResponse.error.message, privacy: .public)"
          )
        } else {
          AppLogger.app.error(
            "openai summary request failed with status \(httpResponse.statusCode, privacy: .public)"
          )
        }
        return nil
      }

      let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
      if let text = decoded.aggregatedOutputText {
        return text
      }
      AppLogger.app.error("openai summary response contained no readable text output")
      return nil
    } catch {
      AppLogger.app.error(
        "openai summary request failed: \(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
  }
}

private struct RequestBody: Encodable {
  let model: String
  let input: String
  let maxOutputTokens: Int

  enum CodingKeys: String, CodingKey {
    case model
    case input
    case maxOutputTokens = "max_output_tokens"
  }
}

private struct ResponseBody: Decodable {
  let outputText: String?
  let output: [OutputItem]?

  enum CodingKeys: String, CodingKey {
    case outputText = "output_text"
    case output
  }

  var aggregatedOutputText: String? {
    if let outputText,
      !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let joined = output?
      .flatMap { $0.content ?? [] }
      .compactMap { item -> String? in
        guard let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else {
          return nil
        }
        return text
      }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return joined?.isEmpty == false ? joined : nil
  }
}

private struct OutputItem: Decodable {
  let type: String?
  let content: [OutputContent]?
}

private struct OutputContent: Decodable {
  let type: String?
  let text: String?
}

private struct ErrorResponse: Decodable {
  let error: APIError
}

private struct APIError: Decodable {
  let message: String
}
