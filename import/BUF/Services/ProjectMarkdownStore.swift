import Foundation

protocol ProjectMarkdownStore: Sendable {
  associatedtype ProjectNoteSnapshot: Sendable

  func prepareProjectDirectory() async throws
  func loadProjectNotesInScope() async throws -> [ProjectNoteSnapshot]
  func loadProjectNotesInScope(at fileURLs: [URL]) async throws -> [ProjectNoteSnapshot]
}
