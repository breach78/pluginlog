import AppKit
import Foundation
import SwiftUI

enum JournalTypography {
  static let baseSize: CGFloat = 16

  static func font(size: CGFloat = baseSize, weight: Font.Weight = .regular) -> Font {
    AppInputTypography.font(size: size, weight: weight)
  }

  static func nsFont(size: CGFloat = baseSize, bold: Bool = false) -> NSFont {
    AppInputTypography.nsFont(size: size, weight: bold ? .bold : .regular)
  }
}

struct JournalNoteDelta {
  let addedLines: [String]
  let removedLines: [String]

  var hasChanges: Bool {
    !addedLines.isEmpty || !removedLines.isEmpty
  }
}

struct JournalRenderedHistoryEvent: Identifiable {
  let event: ProjectHistoryEvent
  let noteDelta: JournalNoteDelta?

  var id: UUID { event.id }
}

struct JournalSystemCluster: Identifiable {
  let id: String
  let projectID: UUID
  let day: Date
  let startAt: Date
  let endAt: Date
  let events: [JournalRenderedHistoryEvent]
  let journalEntries: [ObsidianJournalEntry]
  let presentationStyle: JournalSystemPresentationStyle
}

enum JournalSystemPresentationStyle: String, Codable, Hashable {
  case live
  case retrospective
}

enum JournalRawFeedItem: Identifiable {
  case system(JournalSystemCluster)
  case journal(ObsidianJournalEntry)

  var id: String {
    switch self {
    case .system(let cluster):
      return "system-\(cluster.id)"
    case .journal(let entry):
      return "journal-\(entry.id)"
    }
  }

  var sortDate: Date {
    switch self {
    case .system(let cluster):
      return cluster.startAt
    case .journal(let entry):
      return entry.occurredAt
    }
  }
}

enum JournalTimelineAtom: Identifiable {
  case system(JournalRenderedHistoryEvent)
  case journal(ObsidianJournalEntry)

  var id: String {
    switch self {
    case .system(let event):
      return "atom-system-\(event.id.uuidString)"
    case .journal(let entry):
      return "atom-journal-\(entry.id)"
    }
  }

  var sortDate: Date {
    switch self {
    case .system(let event):
      return event.event.occurredAt
    case .journal(let entry):
      return entry.occurredAt
    }
  }
}

struct JournalRetrospectiveSegment: Identifiable {
  let id: String
  let day: Date
  let events: [JournalRenderedHistoryEvent]
  let journalEntries: [ObsidianJournalEntry]

  var sortDate: Date {
    events.first?.event.occurredAt ?? journalEntries.first?.occurredAt ?? day
  }
}

struct JournalMechanicalGroup: Identifiable, Hashable {
  let id: String
  let title: String
  let lines: [String]
}

enum JournalTone: String, Codable, Hashable {
  case primary
  case secondary
  case added
  case removed
  case commentary
}

enum JournalLineRole: String, Codable, Hashable {
  case summary
  case detail
  case body
  case commentary
}

enum JournalPreparedItemKind: String, Codable, Hashable {
  case system
  case journal
}

enum JournalSummarySource: String, Codable, Hashable {
  case foundation
  case gemini
  case backup
  case fallback
  case unavailable

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)

    switch rawValue {
    case "foundation":
      self = .foundation
    case "gemini":
      self = .gemini
    case "backup":
      self = .backup
    case "fallback", "deterministic":
      self = .fallback
    case "unavailable":
      self = .unavailable
    case "openai", "local", "apple":
      self = .gemini
    default:
      self = .unavailable
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum JournalSummaryRetryTrigger: String, Codable, Hashable, Sendable {
  case userRefreshButton
}

enum JournalSummaryRefreshPolicy: Hashable, Sendable {
  case reuseCachedResults
  case forceRetry(JournalSummaryRetryTrigger)

  var forceRefreshSummary: Bool {
    switch self {
    case .reuseCachedResults:
      return false
    case .forceRetry:
      return true
    }
  }

  var retryTrigger: JournalSummaryRetryTrigger? {
    switch self {
    case .reuseCachedResults:
      return nil
    case .forceRetry(let trigger):
      return trigger
    }
  }
}

enum JournalSummaryFailureReason: String, Codable, Hashable, Sendable {
  case noSummaryInputs
  case foundationModelUnavailable
  case foundationRequestFailed
  case foundationRequestCancelled
  case foundationEmptyResponse
  case geminiRequestFailed
  case geminiRequestCancelled
  case geminiEmptyResponse
  case malformedBackup
  case missingBackup
  case backupProviderMismatch
  case backupSummaryInputMismatch
  case frozenUnavailableSummary
  case frozenFallbackSummary
  case frozenMissingSummaryInputSignature
  case frozenSummaryInputMismatch
  case longTextChunkSummaryUnavailable
  case longTextReduceUnavailable
}

enum JournalLongTextSummaryMode: Hashable, Sendable {
  case emptyInput
  case passthrough
  case singleChunkSummary
  case chunkedSummary
}

enum JournalFrozenSectionReuseDecision: Hashable, Sendable {
  case reuseWithoutDaySummary
  case reuseMatchingCurrentSignature
  case reuseMatchingLegacySignature
  case invalidateBackupSummary
  case invalidateUnavailableSummary
  case invalidateFallbackSummary
  case invalidateMissingSummaryInputSignature
  case invalidateSummaryInputMismatch

  var allowsReuse: Bool {
    switch self {
    case .reuseWithoutDaySummary, .reuseMatchingCurrentSignature, .reuseMatchingLegacySignature:
      return true
    case .invalidateBackupSummary, .invalidateUnavailableSummary, .invalidateFallbackSummary,
      .invalidateMissingSummaryInputSignature, .invalidateSummaryInputMismatch:
      return false
    }
  }
}

enum JournalDaySummaryBackupLoadDecision: Hashable, Sendable {
  case loadedMatchingBackup
  case missingBackup
  case malformedBackup
  case backupProviderMismatch
  case backupSummaryInputMismatch
}

enum JournalDaySummaryBackupPersistenceDecision: Hashable, Sendable {
  case persistGeneratedSummary
  case skipMissingDaySummary
  case skipBackupSummary
  case skipUnavailableSummary
  case skipFallbackSummary
  case skipEmptyMarkdown
}

struct JournalPreparedSegment: Codable, Hashable {
  let text: String
  let tone: JournalTone
  let strikethrough: Bool

  init(_ text: String, tone: JournalTone = .primary, strikethrough: Bool = false) {
    self.text = text
    self.tone = tone
    self.strikethrough = strikethrough
  }
}

struct JournalPreparedLine: Codable, Hashable {
  let role: JournalLineRole
  let segments: [JournalPreparedSegment]
}

struct JournalPreparedMeta: Codable, Hashable {
  let text: String
  let tone: JournalTone
}

struct JournalPreparedItem: Codable, Hashable, Identifiable {
  let id: String
  let sortDate: Date
  let kind: JournalPreparedItemKind
  let label: String
  let isDaySummary: Bool
  let lines: [JournalPreparedLine]
  let detailLines: [JournalPreparedLine]
  let journalLines: [JournalPreparedLine]
  let inlineDetailLineCount: Int
  let meta: [JournalPreparedMeta]
  let summarySource: JournalSummarySource
  let summaryFailureReason: JournalSummaryFailureReason?
  let summaryInputSignature: String?
  let summaryUsage: GeminiGenerateContentSummaryService.SummaryUsage?
  let sourceJournalEntryID: String?
}

struct JournalPreparedDaySection: Codable, Hashable, Identifiable {
  let id: String
  let day: Date
  let title: String
  let summary: String
  let detailLines: [JournalPreparedLine]
  let items: [JournalPreparedItem]
  let isToday: Bool
}
