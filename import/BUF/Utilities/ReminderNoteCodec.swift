import Foundation

struct ReminderNoteCodec {
  struct ParsedNote: Equatable, Sendable {
    let body: String
  }

  static func parse(_ raw: String?) -> ParsedNote {
    ParsedNote(body: ReminderNoteSourceCodec.normalizeReminderRawNote(raw))
  }
}

enum ReminderNoteSourceCodec {
  static let childAnchorPrefix = "buf-child:"

  static func normalize(_ raw: String?) -> String {
    normalizeReminderRawNote(raw)
  }

  static func normalizeReminderRawNote(_ raw: String?) -> String {
    raw?
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .newlines)
      ?? ""
  }
}
