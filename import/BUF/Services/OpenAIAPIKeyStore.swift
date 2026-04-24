import Foundation
import Security

enum OpenAIAPIKeyStoreError: LocalizedError {
  case unexpectedStatus(OSStatus)
  case invalidEncoding

  var errorDescription: String? {
    switch self {
    case .unexpectedStatus(let status):
      return "Keychain access failed (\(status))."
    case .invalidEncoding:
      return "Stored API key could not be decoded."
    }
  }
}

struct OpenAIAPIKeyStore {
  static let shared = OpenAIAPIKeyStore()

  private let service = "com.brainunfog.buf.openai"
  private let account = "api-key"

  func loadAPIKey() throws -> String? {
    var query = baseQuery()
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)

    switch status {
    case errSecSuccess:
      guard let data = item as? Data else {
        throw OpenAIAPIKeyStoreError.invalidEncoding
      }
      guard let key = String(data: data, encoding: .utf8) else {
        throw OpenAIAPIKeyStoreError.invalidEncoding
      }
      return key
    case errSecItemNotFound:
      return nil
    default:
      throw OpenAIAPIKeyStoreError.unexpectedStatus(status)
    }
  }

  func saveAPIKey(_ rawValue: String) throws {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !value.isEmpty else {
      try deleteAPIKey()
      return
    }

    guard let data = value.data(using: .utf8) else {
      throw OpenAIAPIKeyStoreError.invalidEncoding
    }

    let query = baseQuery()
    let updateStatus = SecItemUpdate(
      query as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )

    switch updateStatus {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var createQuery = query
      createQuery[kSecValueData as String] = data
      createQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      let createStatus = SecItemAdd(createQuery as CFDictionary, nil)
      guard createStatus == errSecSuccess else {
        throw OpenAIAPIKeyStoreError.unexpectedStatus(createStatus)
      }
    default:
      throw OpenAIAPIKeyStoreError.unexpectedStatus(updateStatus)
    }
  }

  func deleteAPIKey() throws {
    let status = SecItemDelete(baseQuery() as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw OpenAIAPIKeyStoreError.unexpectedStatus(status)
    }
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
